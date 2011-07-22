#!/bin/bash
cat ${1} | sed s/'Splay ### v..* ###'/"Splay ### v${2} ###"/ > ${1}.2
mv ${1}.2 ${1}
