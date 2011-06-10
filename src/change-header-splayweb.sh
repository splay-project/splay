#!/bin/bash
cat ${1} | sed s/'Splayweb ### v..* ###'/"Splayweb ### v${2} ###"/ > ${1}.2
mv ${1}.2 ${1}
