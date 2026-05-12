#!/usr/bin/env bash
# deploy.sh — Upload WIDOCO-generated site to S3 and invalidate CloudFront cache
#
# Usage:
#   ./deploy.sh                    # uses defaults
#   ./deploy.sh /path/to/docs      # specify WIDOCO output directory
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Terraform already applied (bucket and distribution exist)
#   - WIDOCO output generated via docker-compose

set -euo pipefail

# ---------- Config ----------
BUCKET="schema-default.bco-dmo.org"
VERSION="v1.0"
WIDOCO_DIR="${1:-./docs}"  # WIDOCO output directory (default: ./docs)

# Get CloudFront distribution ID from Terraform output
CF_DIST_ID="E3F01APSK5H9OU"
if [ -z "$CF_DIST_ID" ]; then
  echo "⚠  Could not read CloudFront distribution ID from Terraform."
  echo "   Set it manually: CF_DIST_ID=EXXXXX ./deploy.sh"
  exit 1
fi

echo "=== BCO-DMO Ontology Site Deployment ==="
echo "  Bucket:   s3://${BUCKET}"
echo "  Version:  ${VERSION}"
echo "  Source:    ${WIDOCO_DIR}"
echo "  CF Dist:  ${CF_DIST_ID}"
echo ""

# ---------- Validate source directory ----------
if [ ! -f "${WIDOCO_DIR}/index-en.html" ]; then
  echo "✗ Cannot find ${WIDOCO_DIR}/index-en.html"
  echo "  Run WIDOCO first: docker compose run --rm widoco"
  exit 1
fi

# ---------- Upload HTML files ----------
echo "→ Uploading index.html..."
aws s3 cp "${WIDOCO_DIR}/index-en.html" "s3://${BUCKET}/${VERSION}/index.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "public, max-age=3600"

echo "→ Uploading section HTML files..."
for f in "${WIDOCO_DIR}/sections/"*.html; do
  filename=$(basename "$f")
  aws s3 cp "$f" "s3://${BUCKET}/${VERSION}/sections/${filename}" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "public, max-age=3600"
done

# ---------- Upload CSS ----------
echo "→ Uploading CSS..."
for f in "${WIDOCO_DIR}/resources/"*.css; do
  filename=$(basename "$f")
  aws s3 cp "$f" "s3://${BUCKET}/${VERSION}/resources/${filename}" \
    --content-type "text/css" \
    --cache-control "public, max-age=604800"
done

# ---------- Upload JavaScript ----------
echo "→ Uploading JavaScript..."
for f in "${WIDOCO_DIR}/resources/"*.js; do
  filename=$(basename "$f")
  aws s3 cp "$f" "s3://${BUCKET}/${VERSION}/resources/${filename}" \
    --content-type "application/javascript" \
    --cache-control "public, max-age=604800"
done

# Upload .mjs files if present (dark-mode-toggle.mjs)
for f in "${WIDOCO_DIR}/resources/"*.mjs 2>/dev/null; do
  [ -f "$f" ] || continue
  filename=$(basename "$f")
  aws s3 cp "$f" "s3://${BUCKET}/${VERSION}/resources/${filename}" \
    --content-type "application/javascript" \
    --cache-control "public, max-age=604800"
done

# ---------- Upload ontology serializations ----------
echo "→ Uploading ontology files..."
CONTENT_TYPES=(
  "ontology.ttl:text/turtle"
  "ontology.owl:application/rdf+xml"
  "ontology.jsonld:application/ld+json"
  "ontology.nt:application/n-triples"
)

for entry in "${CONTENT_TYPES[@]}"; do
  file="${entry%%:*}"
  ctype="${entry##*:}"
  if [ -f "${WIDOCO_DIR}/${file}" ]; then
    aws s3 cp "${WIDOCO_DIR}/${file}" "s3://${BUCKET}/${VERSION}/${file}" \
      --content-type "${ctype}" \
      --cache-control "public, max-age=86400"
  fi
done

# Also upload bcodmo.ttl (source ontology)
if [ -f "${WIDOCO_DIR}/../bcodmo.ttl" ]; then
  aws s3 cp "${WIDOCO_DIR}/../bcodmo.ttl" "s3://${BUCKET}/${VERSION}/bcodmo.ttl" \
    --content-type "text/turtle" \
    --cache-control "public, max-age=86400"
fi

# ---------- Upload provenance ----------
echo "→ Uploading provenance..."
if [ -d "${WIDOCO_DIR}/provenance" ]; then
  aws s3 sync "${WIDOCO_DIR}/provenance/" "s3://${BUCKET}/${VERSION}/provenance/" \
    --cache-control "public, max-age=86400"
fi

# ---------- Upload any images/icons ----------
echo "→ Uploading images and icons..."
for f in "${WIDOCO_DIR}/resources/"*.{png,ico,icon,svg,jpg,gif} 2>/dev/null; do
  [ -f "$f" ] || continue
  filename=$(basename "$f")
  aws s3 cp "$f" "s3://${BUCKET}/${VERSION}/resources/${filename}" \
    --cache-control "public, max-age=604800"
done

# ---------- Invalidate CloudFront cache ----------
echo "→ Invalidating CloudFront cache..."
aws cloudfront create-invalidation \
  --distribution-id "${CF_DIST_ID}" \
  --paths "/${VERSION}/*" \
  --query 'Invalidation.Id' \
  --output text

echo ""
echo "✓ Deployment complete!"
echo "  Site: https://${BUCKET}/${VERSION}/"
echo ""
echo "  Test term dereferencing:"
echo "    curl -sI https://${BUCKET}/v0.1/Dataset | grep location"
echo "    → location: /v1.0/index.html#https://schema.bco-dmo.org/v0.1/Dataset"
echo ""
echo "  Test content negotiation:"
echo "    curl -sH 'Accept: text/turtle' https://${BUCKET}/v0.1/ | head"
