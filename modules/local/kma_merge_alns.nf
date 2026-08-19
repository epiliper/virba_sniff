process KMA_MERGE_ALIGNMENTS {
    tag "${meta.id}"
    cpus 20
    memory 128.GB
    container "quay.io/epil02/kma-samtools:1.5.0"

    input:
    tuple val(meta), path(fastq), path(kma_files)
    val db_names
    path db_files
    val sort
    val use_csi

    output:
    tuple val(meta), path("${meta.id}_kma.bam"), emit: bam
    tuple val(meta), path("*.csi"), emit: csi, optional: true
    tuple val(meta), path("*.bai"), emit: bai, optional: true

    script:
    def input = meta.single_end ? "-i ${fastq}" : "-ipe ${fastq}"
    def prefix = meta.id
    def csi = use_csi ? "-c" : ""

    def sort_cmd = sort
        ? """
    samtools sort -@ ${task.cpus} -o ${prefix}.bam ${prefix}_unsorted.bam && \\
        samtools index -@ ${task.cpus} ${csi} ${prefix}_kma.bam && \\
        rm ${prefix}_unsorted.bam
    """
        : """
        mv ${prefix}_unsorted.bam ${prefix}_kma.bam
    """


    """
    kma -nc -nf -na \\
        ${input} \\
        -t_db ${db_names} \\
        -o ${meta.id} -sam \\
        -t ${task.cpus} | samtools view -hb > ${prefix}_unsorted.bam

    ${sort_cmd}
    """
}
