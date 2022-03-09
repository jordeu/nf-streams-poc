


process producer {

  script:
    """
    ## PRE-SCRIPT
    set -x

    # Create output stream
    nf-stream &
    SPID=\$!

    # Find stream http address
    echo "\$(hostname -i)" > .nf-stream

    # Copy stream info to a shared filesystem
    if [ -f "/home/ec2-user/miniconda/bin/aws" ]; then
      /home/ec2-user/miniconda/bin/aws s3 cp .nf-stream ${workDir}/.nf-stream
    else
      cp .nf-stream /tmp/.nf-stream
    fi

    # Wait stream setup
    sleep 1

    ## SCRIPT 

    # Produce some output
    for i in {1..${params.lines}}; do echo "producer line \$i"; sleep 1; done > ./stream.out
    
    ## POST-SCRIPT 

    # Wait nf-stream to finish
    wait \$SPID

    # Remove stream info
    rm /tmp/.nf-stream

    """
}


process consumer {
   publishDir "${params.outdir}", mode: 'copy'

   output:
     path('output.txt')

   script:
     """
     ## PRE-SCRIPT
     set -x

     # Create input stream
     mkfifo stream.in

     # Wait and fetch producer info
     if [ -f "/home/ec2-user/miniconda/bin/aws" ]; then
       until /home/ec2-user/miniconda/bin/aws s3 cp ${workDir}/.nf-stream .nf-stream 2>/dev/null; do sleep 1; done
     else
       until cp /tmp/.nf-stream .nf-stream 2>/dev/null; do sleep 1; done
     fi
     PRODUCER=\$(cat .nf-stream)

     # Wait producer start
     until nc -z \$PRODUCER 9000; do sleep 1; done 
 
     # Read remote stream
     curl -N -o stream.in http://\$PRODUCER:9000/stream &

     ## SCRIPT 

     # Consume stream
     cat ./stream.in | awk '{printf(\$0" consumed!\\n")}' > output.txt     

     ## POST-SCRIPT
     
     # Remove fifo
     rm stream.in
     """
}
