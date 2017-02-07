#!/bin/sh

checkConfig() {
    [ ! -e `dirname $0`/config.sh ] && echo "Error: no config.sh found! Copy config.sh.sample to config.sh and edit it" >&2 && exit 1
}

init() {
    # temp files
    resp=`mktemp /tmp/curl-pgu-json.XXXXX`
    cjar=`mktemp /tmp/curl-pgu-cookies.XXXXX`
}
cleanup() {
    # remove temp files
    [ -e "$cjar" ] && rm $cjar
    [ -e "$resp" ] && rm "$resp"
}

loginPgu() {
    # post login data, follow redirects, check resulting page
    curl -k -L -s -c $cjar 'https://www.mos.ru/api/oauth20/v1/frontend/json/ru/process/enter?redirect=https%3A%2F%2Fmy.mos.ru%2Fmy%2F' >> /dev/null
    if ! curl -k -L -s -c $cjar -b $cjar "https://oauth20.mos.ru/sps/j_security_check?j_username=$login&j_password=$password&accessType=alias" \
    |  grep -q "SURNAME"; then
        echo "Login failed!" >&2
        cleanup
        exit 1
    fi
}

getWaterCounterIds() {
    eval `cat $resp |  jq -r '.counter | sort_by(.type)[] | "type", .type, .counterId' | paste -sd '_=;' -`
}

getWaterIndications() {
    # get water counters
    curl -k -L -s -c $cjar -b $cjar -k "https://www.mos.ru/pgu/ru/application/guis/1111/?getCountersInfo=true&requestParams%5BpaycodeFlat%5D%5Bpaycode%5D=$paycode&requestParams%5BpaycodeFlat%5D%5Bflat%5D=$kv"
}

removeWaterIndication() {
    curl -c $cjar -b $cjar -k -s -d "removeCounterIndication=true&values%5Bpaycode%5D=$paycode&values%5BcounterId%5D=$1" https://pgu.mos.ru/ru/application/guis/1111/ > /dev/null
}

setWaterIndications() {
    hot="$1"
    cold="$2"
    [ "$hot" -gt "$cold" ] && echo "Error: Hot counter value ($hot) > cold counter value ($cold)!" && exit 1
    curl -c $cjar -b $cjar -k -s -d "addCounterInfo=true&values%5Bpaycode%5D=$paycode&values%5Bindications%5D%5B0%5D%5BcounterNum%5D=$type_1&values%5Bindications%5D%5B0%5D%5BcounterVal%5D=$cold&values%5Bindications%5D%5B0%5D%5Bperiod%5D=$dt&values%5Bindications%5D%5B0%5D%5Bnum%5D=" https://pgu.mos.ru/ru/application/guis/1111/  > /dev/null
    curl -c $cjar -b $cjar -k -s -d "addCounterInfo=true&values%5Bpaycode%5D=$paycode&values%5Bindications%5D%5B0%5D%5BcounterNum%5D=$type_2&values%5Bindications%5D%5B0%5D%5BcounterVal%5D=$hot&values%5Bindications%5D%5B0%5D%5Bperiod%5D=$dt&values%5Bindications%5D%5B0%5D%5Bnum%5D=" https://pgu.mos.ru/ru/application/guis/1111/  > /dev/null
}

getMosenergoData() {
    eval `curl -c $cjar -b $cjar -k -s 'https://pgu.mos.ru/common/ajax/index.php' \
        --data "ajaxModule=Mosenergo&ajaxAction=qMpguCheckShetch&items%5Bcode%5D=$mosenergo_accnum&items%5Bnn_schetch%5D=$mosenergo_cntnum"  \
            | jq ".result" | sed -Ene 's/ +"(id_kng|schema)": "(.*)",?$/\1="\2"/p'`
    eval `curl -c $cjar -b $cjar -k -s 'https://pgu.mos.ru/common/ajax/index.php' \
        --data "ajaxModule=Mosenergo&ajaxAction=qMpguGetLastPok&items%5Bcode%5D=$mosenergo_accnum&items%5Bid_kng%5D=$id_kng&items%5Bs%D1%81hema%5D=$schema" \
            | jq ".result" | sed -Ene 's/ +"(pok_t1|pok_t2|pok_t3|dt_obrz)": "(.*)",?$/\1="\2"/p'`
}

printMosenergoLastValues() {
    echo "Previously sent values:"
    echo "Date		T1	T2	T3"
    echo "${dt_obrz%T*}	$pok_t1	$pok_t2	$pok_t3"
}

setMosenergoIndications() {
    t1="$1"
    t2=0
    t3=0
    [ "$#" -ge "2" ] && [ "$2" -gt "0" ] && t2="$2"
    [ "$#" -ge "3" ] && [ "$3" -gt "0" ] && t3="$3"
    curl -c $cjar -b $cjar -k -s "https://pgu.mos.ru/common/ajax/index.php" \
        --data "ajaxModule=Mosenergo&ajaxAction=qMpguDoTransPok&items%5Bid_kng%5D=$id_kng&items%5Bcode%5D=$mosenergo_accnum&items%5Bvl_pok_t1%5D=$t1&items%5Bvl_pok_t2%5D=$t2&items%5Bvl_pok_t3%5D=$t3&items%5Bs%D1%81hema%5D=$schema" \
            | jq ""
}

getLastDayOfMonth() {
    if [ `uname` = "Linux" ]; then
        dt=`date -d "$(date +'%Y-%m-1') +1 month -1 day" +'%Y-%m-%d'`
    else
        dt=`date -v1d -v+1m -v-1d +'%Y-%m-%d'`
    fi
}

printWaterHistory() {
    echo "History of values"
    echo "Date		Hot	Cold"
    cat $resp | jq -r ".counter | sort_by(.type)[] | .indications[] | .period, .indication"  | paste -sd '	\n' - | sort | paste -sd '	\n' - | cut -f 1,2,4| sed -Ee 's/\+03:00//'
}

printWaterLastValues() {
    echo "Last set values (cold,hot): "
    getWaterIndications | jq -r ".counter | sort_by(.type)[] | .indications[] | select(.period==\"$dt+03:00\").indication" | paste -sd ',' -
}
