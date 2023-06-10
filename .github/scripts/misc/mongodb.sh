#!/bin/bash
set -ex
python3 -c "import minio" || sudo pip install minio 
source .github/scripts/common/common.sh

[[ -z "$META" ]] && META=redis
source .github/scripts/start_meta_engine.sh
start_meta_engine $META
META_URL=$(get_meta_url $META)

RECORD_COUNT=100000
OPERATION_COUNT=1500

if [ ! -d mongodb-linux-x86_64-3.0.0 ]; then 
    git clone https://github.com/sanwan/actionsoftware.git
    tar zxvf actionsoftware/mongodb-linux-x86_64-3.0.0.tgz
fi

if [ ! -d ycsb-0.5.0 ]; then 
    wget  -q https://github.com/brianfrankcooper/YCSB/releases/download/0.5.0/ycsb-0.5.0.tar.gz
    tar -zxvf ycsb-0.5.0.tar.gz
fi

test_mango_db()
{
    prepare_test
    ./juicefs format $META_URL myjfs --trash-days 0
    ./juicefs mount -d $META_URL /jfs --enable-xattr --cache-size 3072 --no-usage-report
    mkdir /jfs/mongodb/
    nohup mongodb-linux-x86_64-3.0.0//bin/mongod --dbpath /jfs/mongodb &
    sleep 3s
    ps -aux | grep mongo
    sed -i "s?recordcount=1000?recordcount=$RECORD_COUNT?" ycsb-0.5.0/workloads/workloadf
    sed -i "s?operationcount=1000?operationcount=$OPERATION_COUNT?" ycsb-0.5.0/workloads/workloadf
    grep recordcount ycsb-0.5.0/workloads/workloadf
    grep operationcount ycsb-0.5.0/workloads/workloadf
    time ycsb-0.5.0/bin/ycsb load mongodb -s -P ycsb-0.5.0/workloads/workloadf  -threads 10 > outputLoad.txt
    ps -aux | grep mongo
    echo "run read modify write"
    time ycsb-0.5.0/bin/ycsb run mongodb -s -P ycsb-0.5.0/workloads/workloadf -threads 10 > outputRun.txt
}
          
prepare_test()
{
    umount_jfs /jfs $META_URL
    python3 .github/scripts/flush_meta.py $META_URL
    rm -rf /var/jfs/myjfs || true
}

function_names=$(sed -nE '/^test_[^ ()]+ *\(\)/ { s/^\s*//; s/ *\(\).*//; p; }' "$0")
for func in ${function_names}; do
    echo Start Test: $func
    START_TIME=$(date +%s)
    "${func}"
    END_TIME=$(date +%s)
    ELAPSED_TIME=$((END_TIME - START_TIME))
    echo Finish Test: $func succeeded
done

