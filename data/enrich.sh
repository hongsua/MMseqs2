#!/bin/sh -ex
# Iterative sequence search workflow script
fail() {
    echo "Error: $1"
    exit 1
}

notExists() {
	[ ! -f "$1" ]
}

#pre processing
[ -z "${MMSEQS}" ] && echo "Please set the environment variable \$MMSEQS to your MMSEQS binary." && exit 1;
# check amount of input variables
[ "$#" -ne 6 ] && echo "Please provide <queryDB> <targetDB> <targetRes> <targetProf> <outDB> <tmp>" && exit 1;
# check if files exists
[ ! -f "$1" ] &&  echo "$1 not found!" && exit 1;
[ ! -f "$2" ] &&  echo "$2 not found!" && exit 1;
[ ! -f "$3" ] &&  echo "$3 not found!" && exit 1;
[ ! -f "$4" ] &&  echo "$4 not found!" && exit 1;
[   -f "$5" ] &&  echo "$5 exists already!" && exit 1;
[ ! -d "$6" ] &&  echo "tmp directory $6 not found!" && mkdir -p "$6";

QUERYDB="$1"
PROFTARGETSEQ="$2"
PROFRESULT="$3"
TARGETPROF="$4"
RESULT="$5"
TMP_PATH="$6"

if notExists "${TMP_PATH}/search_slice"; then
    # shellcheck disable=SC2086
    "${MMSEQS}" search "${QUERYDB}" "${TARGETPROF}" "${TMP_PATH}/search_slice" "${TMP_PATH}/slice_tmp" ${PROF_SEARCH_PAR} \
        || fail "search died"
fi

if notExists "${TMP_PATH}/prof_slice"; then
    # shellcheck disable=SC2086
    ${RUNNER} "${MMSEQS}" result2profile "${QUERYDB}" "${TARGETPROF}" "${TMP_PATH}/search_slice" "${TMP_PATH}/prof_slice" ${PROF_PROF_PAR} \
        || fail "result2profile died"
fi

INPUT="${TMP_PATH}/prof_slice"
STEP=0
while [ "${STEP}" -lt "${NUM_IT}" ]; do
    # call prefilter module
    if notExists "${TMP_PATH}/pref_${STEP}"; then
        PARAM="PREFILTER_PAR_${STEP}"
        eval TMP="\$$PARAM"
        # shellcheck disable=SC2086
        ${RUNNER} "${MMSEQS}" prefilter "${INPUT}" "${TARGETPROF}_consensus" "${TMP_PATH}/pref_${STEP}" ${TMP} \
            || fail "prefilter died"
    fi

    if [ ${STEP} -ge 1 ]; then
        if notExists "${TMP_PATH}/pref_${STEP}.hasnext"; then
            # shellcheck disable=SC2086
            "${MMSEQS}" subtractdbs "${TMP_PATH}/pref_${STEP}" "${TMP_PATH}/aln_0" "${TMP_PATH}/pref_next_${STEP}" ${SUBSTRACT_PAR} \
                || fail "subtractdbs died"
            mv -f "${TMP_PATH}/pref_next_${STEP}" "${TMP_PATH}/pref_${STEP}"
            mv -f "${TMP_PATH}/pref_next_${STEP}.index" "${TMP_PATH}/pref_${STEP}.index"
            touch "${TMP_PATH}/pref_${STEP}.hasnext"
        fi
    fi

	# call alignment module
	if notExists "${TMP_PATH}/aln_${STEP}"; then
	    PARAM="ALIGNMENT_PAR_${STEP}"
        eval TMP="\$$PARAM"
        # shellcheck disable=SC2086
        ${RUNNER} "${MMSEQS}" "${ALIGN_MODULE}" "${INPUT}" "${TARGETPROF}_consensus" "${TMP_PATH}/pref_${STEP}" "${TMP_PATH}/aln_${STEP}" ${TMP} \
            || fail "${ALIGN_MODULE} died"
    fi

    if notExists "${TMP_PATH}/aln_${STEP}.hasexpand"; then
        PARAM="EXPAND_PAR_${STEP}"
        eval TMP="\$$PARAM"
        # shellcheck disable=SC2086
        "${MMSEQS}" expandaln "${INPUT}" "${PROFTARGETSEQ}" "${TMP_PATH}/aln_${STEP}" "${PROFRESULT}" "${TMP_PATH}/aln_exp_${STEP}" ${TMP} \
            || fail "expandaln died"
        mv -f "${TMP_PATH}/aln_exp" "${TMP_PATH}/aln_0"
        mv -f "${TMP_PATH}/aln_exp.index" "${TMP_PATH}/aln_0.index"
        touch "${TMP_PATH}/aln_exp_${STEP}.hasexpand"
    fi

    if [ ${STEP} -gt 0 ]; then
        if notExists "${TMP_PATH}/aln_${STEP}.hasmerge"; then
            # shellcheck disable=SC2086
            "${MMSEQS}" mergedbs "${INPUT}" "${TMP_PATH}/aln_new" "${TMP_PATH}/aln_0" "${TMP_PATH}/aln_${STEP}" ${VERBOSITY_PAR} \
                || fail "mergedbs died"
            mv -f "${TMP_PATH}/aln_new" "${TMP_PATH}/aln_0"
            mv -f "${TMP_PATH}/aln_new.index" "${TMP_PATH}/aln_0.index"
            touch "${TMP_PATH}/aln_${STEP}.hasmerge"
        fi
    fi

    # create profiles
    if notExists "${TMP_PATH}/profile_${STEP}"; then
        PARAM="PROFILE_PAR_${STEP}"
        eval TMP="\$$PARAM"
        # shellcheck disable=SC2086
        ${RUNNER} "${MMSEQS}" result2profile "${QUERYDB}" "${PROFTARGETSEQ}" "${TMP_PATH}/aln_0" "${TMP_PATH}/profile_${STEP}" ${TMP} \
            || fail "result2profile died"
    fi
	INPUT="${TMP_PATH}/profile_${STEP}"

	STEP=$((STEP+1))
done

(mv -f "${TMP_PATH}/aln_0" "${RESULT}" && mv -f "${TMP_PATH}/aln_0.index" "${RESULT}.index") || fail "Could not move result to ${RESULT}"

if [ -n "$REMOVE_TMP" ]; then
 echo "Remove temporary files"
 STEP=0
 while [ "${STEP}" -lt "$NUM_IT" ]; do
    rm -f "${TMP_PATH}/pref_${STEP}" "${TMP_PATH}/pref_${STEP}.index"
    rm -f "${TMP_PATH}/aln_${STEP}" "${TMP_PATH}/aln_${STEP}.index"
    rm -f "${TMP_PATH}/profile_${STEP}" "${TMP_PATH}/profile_${STEP}.index" "${TMP_PATH}/profile_${STEP}_h" "${TMP_PATH}/profile_${STEP}_h.index"
    rm -f "${TMP_PATH}/aln_${STEP}.hasmerge" "${TMP_PATH}/aln_exp_${STEP}.hasexpand" "${TMP_PATH}/pref_${STEP}.hasnext"
    STEP=$((STEP+1))
 done
 rm -f "${TMP_PATH}/prof_slice" "${TMP_PATH}/prof_slice.index"
 rm -f "${TMP_PATH}/search_slice" "${TMP_PATH}/search_slice.index"
 rm -f "${TMP_PATH}/enrich.sh"
fi
