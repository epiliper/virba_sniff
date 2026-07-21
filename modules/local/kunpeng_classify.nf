process KUNPENG_CLASSIFY {
    tag "${meta.id}"
    cpus 4
    memory 16.GB
    time 4.H
    container "quay.io/epil02/kun_peng:0.7.12"

    input:
    tuple val(meta), path(reads)
    val conf_thres
    val min_fastq_score
    val db
    val emit_minimizers

    output:
    tuple val(meta), path('*kreport*'), emit: report
    tuple val(meta), path("*${meta.id}*.txt"), emit: assignment

    script:
    def prefix = meta.id
    def pe = meta.single_end ? "" : "--paired-end-processing"
    def minimizers = emit_minimizers ? "--report-kmer-data" : ""
    def batch_size = (task.memory.toGiga() / 1.5).toInteger()
    batch_size = batch_size < 1 ? 1 : batch_size

    """
    kun_peng classify \\
        --minimum-quality-score ${min_fastq_score} \\
        --confidence-threshold ${conf_thres} \\
        ${minimizers} \\
        --batch-size ${batch_size} \\
        --num-threads 4 ${reads} ${pe} --db ${db} --chunk-dir chunks --output-dir kp

    mv kp/output_1.kreport2 ${prefix}.kreport2
    mv kp/output_1.txt ${prefix}.txt
    """
    
    }
