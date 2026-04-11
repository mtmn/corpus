#!/bin/bash
aws s3api put-bucket-policy \
  --bucket mtmn-scrobbler-data \
  --policy file://policy.json \
  --endpoint-url https://estri.saatana.cat
