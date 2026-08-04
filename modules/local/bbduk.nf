process BBMAP_BBDUK {
    tag "${meta.id}"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/5a/5aae5977ff9de3e01ff962dc495bfa23f4304c676446b5fdf2de5c7edfa2dc4e/data'
        : 'community.wave.seqera.io/library/bbmap_pigz:07416fe99b090fa9'}"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path('*.fastq.gz'), emit: reads
    tuple val(meta), path('*.log'), emit: log
    tuple val("${task.process}"), val('bbmap'), eval('bbversion.sh | grep -v "Duplicate cpuset"'), emit: versions_bbmap, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def BBDUK_ENTROPY_FLAGS = "entropy=0.7 entropywindow=20 entropymask=t"
    def prefix = task.ext.prefix ?: "${meta.id}"
    def raw = meta.single_end ? "in=${reads[0]}" : "in1=${reads[0]} in2=${reads[1]}"
    def trimmed = meta.single_end ? "out=${prefix}.fastq.gz" : "out1=${prefix}_1.fastq.gz out2=${prefix}_2.fastq.gz"

    """
    bbduk.sh \\
        -Xmx${task.memory.toGiga()}g \\
        ${raw} \\
        ${trimmed} \\
        threads=${task.cpus} \\
        ${BBDUK_ENTROPY_FLAGS} \\
        &> ${prefix}.bbduk.log
    """
}
