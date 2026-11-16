# Test modules

Real module files, in the on-disk format SWORD uses, kept in this package so that `ScriptureText`'s parsers are tested
on real data wherever the package is built: no SWORD engine, no download and no data outside the repository. They are
read by `ScriptureTextTestSupport` (`ModuleFiles`, `TestModulesReader`), which needs only Foundation; the tests are in
`Tests/ScriptureTextModulesTests`. This folder belongs to the package and moves with it.

| Folder | Module | Driver and markup | Licence stated in its `.conf` | Notes |
|---|---|---|---|---|
| `KJV/` | King James Version (1769) with Strong's numbers and morphology, v2.9 | zText, OSIS | "General public license for distribution for any purpose" | The same module the app ships; its search index is left out. The conf notes that the Crown of England holds the rights to the base text. |
| `YLT/` | Young's Literal Translation (1898), v1.1 | zText, GBF | Public Domain | |
| `Weymouth/` | Weymouth New Testament (1912), v1.1 | zText, GBF | Public Domain | New Testament only |
| `DTN/` | Darby Translation Notes, v1.0 | RawCom, GBF | Public Domain | |
| `TFG/` | The Fourfold Gospel and Commentary on Acts (McGarvey and Pendleton), v1.5 | RawCom, GBF | Public Domain | New Testament only |
| `USFM/eng-kjv2006/` | King James Version (1769) with Strong's numbers, from eBible.org | USFM 3, three book files (Genesis, Psalms, John) | Public Domain (`copr.htm`, kept beside them) | Not a SWORD module: the USFM parser's fixture, checked verse by verse against `KJV/` (plan Track V4). eBible's text is CrossWire's KJV; the same UK Crown-patent note applies |

Source: CrossWire's module repository (`rawzip` packages), unzipped. Only public-domain modules, and the KJV the app
already ships, belong here. **Do not add** a module whose conf says "Copyrighted" even when CrossWire may distribute it
(RusVZh, LXX, Azeri and the Chinese Strong's modules are examples): the licence to CrossWire is not a licence to this
repository.

## Larger, restricted data

Some tests run over more modules than can be committed: all the OSIS Bibles (about 10,000 chapters), the TEI and
ThML dictionaries, the Strong's-tagged GBF Bible. They read a folder of exported entries that the developer builds
locally from the modules and points to with an environment variable (`SCRIPTURE_CORPUS_DIR`, `SCRIPTURE_DICT_DIR`,
`SCRIPTURE_THML_DIR`, `SCRIPTURE_GBF_DIR`; see the `enabled(if:)` tests). Without the variable those tests are skipped,
so a fresh clone runs only the committed data in this folder. The exporter scripts live outside the repository, with
the restricted modules.

Each folder is a SWORD module root (`mods.d/<name>.conf` and `modules/…`), so a folder can also be given to
`SwordManager` for a real-SWORD test.
