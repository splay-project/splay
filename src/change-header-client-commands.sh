#!/bin/bash
cat ${1} | sed s/'Splay Client Commands ### v..* ###'/"Splay Client Commands ### v${2} ###"/ > ${1}.2
mv ${1}.2 ${1}
