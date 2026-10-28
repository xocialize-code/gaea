# Vendored MES schemas

`common.schema.json` and `descriptor.schema.json` from media-engine-spec at tag **v0.5.0** (`7f25bbb`),
`schemas/v0/base/`, copied unchanged. Gaea's manifest refers to them for MES offers (`ModelOffer`), parameter
properties and shared definitions, so a plugin's offer is checked by the same rules MES clients check descriptors by.

Refresh by copying both files from a newer MES tag and running `python3 tools/validate.py` and
`python3 tools/test_validator.py`.
