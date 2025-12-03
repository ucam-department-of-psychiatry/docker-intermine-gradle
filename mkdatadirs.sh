#!/bin/bash

set -euo pipefail

THIS_DIR=$(dirname "$0")

mkdir -p \
    "${THIS_DIR}"/data/bluegenes_tools \
    "${THIS_DIR}"/data/mine/dump \
    "${THIS_DIR}"/data/mine/configs \
    "${THIS_DIR}"/data/mine/packages \
    "${THIS_DIR}"/data/mine/intermine \
    "${THIS_DIR}"/data/postgres \
    "${THIS_DIR}"/data/solr

sudo chown -R 8983:8983 "${THIS_DIR}"/data/solr

echo "Don't forget to also mkdir ${THIS_DIR}/data/mine/<your mine name>"
