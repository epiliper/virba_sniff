process MINIMAP2_BIG {
    tag "${meta.id}"
    // container "quay.io/epil02/minimap2_312_pigz:0.01"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/37/37671219cfd244eb9b33db9345d3543ffd83037419a1c57f4648aace493ec2c2/data'
        : 'community.wave.seqera.io/library/minimap2_samtools:b09096fc890429ce'}"
    cpus 8
    memory 64.GB

    input:
    tuple val(meta), path(fastq)
    val mmi_index

    output:
    // tuple val(meta), path("*.paf.gz"), emit: paf
    tuple val(meta), path("*.bam"), emit: bam
    tuple val(meta), path("*.bai"), emit: bai

    script:
    def prefix = meta.id

    """
    minimap2 -t ${task.cpus} \\
        ${mmi_index} \\
        ${fastq} \\
        --secondary no \\
        -K 100M -a -x sr --eqx -z 800,200 \\
        --split-prefix ${meta.id}_pt2 | samtools view -hb -F 2308 > ${prefix}_unsorted

    samtools sort -@ ${task.cpus} -o ${prefix}.bam ${prefix}_unsorted
    samtools index -@ ${task.cpus} ${prefix}.bam && rm ${prefix}_unsorted

    #cpus 32
    #memory 128.GB

    # pigz -4 -c > ${prefix}.paf.gz
    """
}
