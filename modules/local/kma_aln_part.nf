// note: the version of KMA used to align must match the version used to make the indexes.
process KMA_ALIGN_PARTITION {
    tag "${meta.id}_${db_meta}"
    cpus 30
    memory 128.GB

    container "quay.io/epil02/kma-samtools:1.5.0"

    // container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
    //     ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/4f/4fc6c961562aef21c24b4f2330d9cd7e9bbda162b0d584a5cd5428e0b725e0d6/data'
    //     : 'community.wave.seqera.io/library/kma:1.5.0--eb093e0381fb59ea'}"

    input:
    tuple val(meta), path(fastq), val(db_meta), val(db_names), path(db)

    output:
    tuple val(meta), path("${meta.id}*"), emit: kma_files

    script:

    def input = meta.single_end ? "-i ${fastq}" : "-ipe ${fastq}"

    """
    kma -nc -nf -na \\
        ${input} \\
        -mem_mode \\
        -spltDB \\
        -s2 \\
        -t_db ${db_names} \\
        -t ${task.cpus} -sam \\
        -o ${meta.id} > ${meta.id}.${db_meta}
    """
}
