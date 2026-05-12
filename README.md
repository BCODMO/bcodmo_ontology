# bcodmo_ontology

1. Update .ttl file
2. Run `docker compose run --rm widoco`
3. Check at `ontology.owl` at: https://oops.linkeddata.es/report.jsp


## Before uploading to s3://schema.bco-dmo.org

1. Rename index-en.html to index.html
2. Fix citation section
    - Line 59: `$("#citation").load("sections/citation.html");`
    - Remove the WIDOCO citation and replace with `<dd><div id="citation"></div></dd></dl>`
3. Remove `<a href="provenance/provenance-en.html" target="_blank">Provenance of this page</a><hr/>`

## After uploading to S3

1. `aws cloudfront create-invalidation --distribution-id **** --paths "/*"`
