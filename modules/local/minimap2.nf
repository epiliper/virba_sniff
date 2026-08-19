process MINIMAP2_BIG {
    tag "${meta.id}"
    container "quay.io/epil02/rammap-samtools:1.1.2-1.24"
    cpus 64
    memory 128.GB

    input:
    tuple val(meta), path(fastq)
    val mmi_index
    val sort_by_name
    val suffix
    val use_csi

    output:
    // tuple val(meta), path("*.paf.gz"), emit: paf
    tuple val(meta), path("*${suffix}*.bam"), emit: bam
    tuple val(meta), path("*${suffix}*.bai"), emit: bai, optional: true
    tuple val(meta), path("*${suffix}*.csi"), emit: csi, optional: true

    script:
    def prefix = meta.id
    def csi = use_csi ? "-c" : ""

    def sort_and_index = sort_by_name
        ? "samtools sort -N -@ ${task.cpus} -o ${prefix}_${suffix}.bam ${prefix}_unsorted"
        : "samtools sort -@ ${task.cpus} -o ${prefix}_${suffix}.bam ${prefix}_unsorted && samtools index -@ ${task.cpus} ${csi} ${prefix}_${suffix}.bam"

    """
    mkdir -p ${prefix}
    rammap -t ${task.cpus} \\
        --secondary no \\
        -K 4G -a --eqx -z 4000,200 \\
        --split-prefix ${prefix}/${meta.id}_pt2  \\
        ${mmi_index} \\
        ${fastq} | samtools view -hb -F 2308 > ${prefix}_unsorted

    ${sort_and_index} && rm ${prefix}_unsorted
    """
}
