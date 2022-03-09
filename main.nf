
// Default output directory
scheme = workDir.toUri().scheme
params.outdir = "${scheme}:${scheme!='file'?'/':''}${workDir}/results"

// How many lines will emit the producer
params.lines = 10

// Producers channel
(producers, consumers) = Channel.from( 's01', 's02' ).into(2)
consumers = consumers.combine( Channel.from( '1_of_3', '2_of_3', '3_of_3') )

process producer {
  tag "stream $stream_id"

  input:
    val stream_id from producers

  script:
    """
    ## PRE-SCRIPT
    set -x

    # Create output stream
    nf-stream -stream=${stream_id} > .nf-stream-${stream_id}.log 2>&1 &
    SPID=\$!

    # Wait stream info file
    until [ -f ".nf-stream-${stream_id}" ]; do sleep 1; done

    # Copy stream info to a shared filesystem
    if [ -f "/home/ec2-user/miniconda/bin/aws" ]; then
      /home/ec2-user/miniconda/bin/aws s3 cp .nf-stream-${stream_id} s3:/${workDir}/.nf-stream-${stream_id}
    else
      cp .nf-stream-${stream_id} /tmp/.nf-stream-${stream_id}
    fi

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

     # Wait and fetch stream info
     if [ -f "/home/ec2-user/miniconda/bin/aws" ]; then
       until /home/ec2-user/miniconda/bin/aws s3 cp s3:/${workDir}/.nf-stream-${stream_id} .nf-stream-${stream_id} 2>/dev/null; do sleep 1; done
     else
       until cp /tmp/.nf-stream-${stream_id} .nf-stream-${stream_id} 2>/dev/null; do sleep 1; done
     fi
     STREAM_INFO=\$(cat .nf-stream-${stream_id})

     # Wait producer start
     until nc -z \${STREAM_INFO/:/ }; do sleep 1; done 
 
     # Read remote stream
     curl -N -o stream.in -H "NF_STREAM_CONSUMER: ${consumer_id}" http://\${STREAM_INFO}/stream &

     ## SCRIPT 

     # Consume stream
     cat ./stream.in | awk '{printf(\$0" consumed by ${consumer_id}\\n")}' > stream_${stream_id}_${consumer_id}_output.txt     

     ## POST-SCRIPT
     
     # Remove fifo
     rm stream.in
     """
}
