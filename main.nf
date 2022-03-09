
// Default parameters
params.outdir = "${workDir}/results"      // Default output directory
params.lines = 10                         // How many lines will emit the producer

// Producers channel
(producers, consumers) = Channel.from( 's01' ).into(2)
consumers = consumers.combine( Channel.from( '1_of_2', '2_of_2') )

process producer {
  tag "stream $stream_id"

  input:
    val stream_id from producers

  script:
    """
    ## PRE-SCRIPT
    set -x

    # Create output stream
    nf-stream &
    SPID=\$!

    # Find stream http address
    echo "\$(hostname -i)" > .nf-stream-${stream_id}

    # Copy stream info to a shared filesystem
    if [ -f "/home/ec2-user/miniconda/bin/aws" ]; then
      /home/ec2-user/miniconda/bin/aws s3 cp .nf-stream-${stream_id} s3:/${workDir}/.nf-stream-${stream_id}
    else
      cp .nf-stream-${stream_id} /tmp/.nf-stream-${stream_id}
    fi

    # Wait stream setup
    sleep 1

    ## SCRIPT 

    # Produce some output
    for i in {1..${params.lines}}; do echo "stream ${stream_id} line \$i"; sleep 1; done > ./stream.out
    
    ## POST-SCRIPT 

    # Wait nf-stream to finish
    wait \$SPID

    # Remove stream info
    [[ -f "/tmp/.nf-stream-${stream_id}" ]] && rm /tmp/.nf-stream-${stream_id}

    # Done
    exit 0

    """
}


process consumer {
   tag "stream $stream_id - consumer $consumer_id"
   publishDir "${params.outdir}", mode: 'copy'

   input:
     tuple val(stream_id), val(consumer_id) from consumers

   output:
     path('*output.txt')

   script:
     """
     ## PRE-SCRIPT
     set -x

     # Create input stream
     mkfifo stream.in

     # Wait and fetch producer info
     if [ -f "/home/ec2-user/miniconda/bin/aws" ]; then
       until /home/ec2-user/miniconda/bin/aws s3 cp s3:/${workDir}/.nf-stream-${stream_id} .nf-stream-${stream_id} 2>/dev/null; do sleep 1; done
     else
       until cp /tmp/.nf-stream-${stream_id} .nf-stream-${stream_id} 2>/dev/null; do sleep 1; done
     fi
     PRODUCER=\$(cat .nf-stream-${stream_id})

     # Wait producer start
     until nc -z \$PRODUCER 9000; do sleep 1; done 
 
     # Read remote stream
     curl -N -o stream.in -H "NF_STREAM_CONSUMER: ${consumer_id}" http://\$PRODUCER:9000/stream &

     ## SCRIPT 

     # Consume stream
     cat ./stream.in | awk '{printf(\$0" consumed by ${consumer_id}\\n")}' > stream_${stream_id}_${consumer_id}_output.txt     

     ## POST-SCRIPT
     
     # Remove fifo
     rm stream.in
     """
}
