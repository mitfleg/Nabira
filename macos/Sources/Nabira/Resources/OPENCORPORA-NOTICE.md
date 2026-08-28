# OpenCorpora dictionary notice

`yoficator.tsv` is a modified, reduced database derived from the Russian
morphological dictionary of [OpenCorpora](https://opencorpora.org/) through
`pymorphy3-dicts-ru`.

- OpenCorpora source dictionary revision: 417150
- pymorphy3 corpus revision: 4580142
- Changes: only word forms containing `ё` were retained; `ё` was replaced with
  `е` to form lookup keys; entries with an existing `е` spelling or multiple
  possible `ё` spellings were removed.
- Data license: [Creative Commons Attribution-ShareAlike 3.0 Unported](https://creativecommons.org/licenses/by-sa/3.0/)

The Nabira source code remains licensed under the MIT License. The derived
`yoficator.tsv` database is distributed under CC BY-SA 3.0.
