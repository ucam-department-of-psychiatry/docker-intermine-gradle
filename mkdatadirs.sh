#!/usr/bin/env sh

mkdir -p \
    ./data/mine/dump \
    ./data/mine/configs \
    ./data/mine/packages \
    ./data/mine/intermine \
    ./data/postgres \
    ./data/solr

sudo chown -R 8983:8983 ./data/solr

echo "Don't forget to also mkdir ./data/mine/<your mine name>"
