# KMA and samtools image

This Ubuntu image installs KMA 1.5.0 and samtools 1.22.1 from their upstream
source releases. It has Bash, `procps`, and no entrypoint, as expected by
Nextflow task scripts.

```bash
docker build --platform linux/amd64 \
  -t kma-samtools:1.5.0 \
  docker/kma_samtools
```

Use the image in a Nextflow process after publishing it to a registry:

```nextflow
process KMA_ALIGN {
    container 'REGISTRY/kma-samtools:1.5.0'

    script:
    """
    kma -i reads.fastq.gz -t_db database -o result -sam \
        | samtools view -b -o result.bam
    """
}
```

KMA remains at 1.5.0 because KMA indexes must be used with the matching KMA
version.
