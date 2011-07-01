#!/bin/bash
cat ${1} | sed s/'Splay Controller ### v..* ###'/"Splay Controller ### v${2} ###"/ > ${1}.2
mv ${1}.2 ${1}
