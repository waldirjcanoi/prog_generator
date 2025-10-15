# Debug: parse properties file and print parsed maps (globals + fields)
# Usage: awk -f scripts/dump_conf.awk /path/to/your.conf

function trim(s){ gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }

function parse_prop_line(line,    seppos, keypart, valpart, k) {
    seppos = index(line, ":")
    if (seppos == 0) seppos = index(line, "=")
    if (seppos == 0) return
    keypart = trim(substr(line, 1, seppos-1))
    valpart = trim(substr(line, seppos+1))
    # ignore legacy indexed keys like name[1]
    if (keypart ~ /\[[0-9]+\]$/) return
    if (current_section ~ /^field(_|)([0-9]+)$/) {
        if (match(current_section, /([0-9]+)$/, sarr)) {
            k = sarr[1] + 0
        } else {
            maxField++
            k = maxField
        }
        field[k, keypart] = valpart
        fieldKeys[keypart] = 1
        if (k > maxField) maxField = k
    } else {
        globals[keypart] = valpart
    }
}

FNR==1 { current_section = "global" }
{
    line = $0
    gsub(/\r/, "", line)
    line = trim(line)
    if (line == "" || line ~ /^[;#]/) next
    if (match(line, /^\[([^\]]+)\]/, sec)) { current_section = trim(sec[1]); next }
    parse_prop_line(line)
}
END {
    print "=== GLOBALS ==="
    for (k in globals) print k " = " globals[k]
    print ""
    print "=== FIELDS ==="
    for (idx = 1; idx <= maxField; idx++) {
        print "--- field[" idx "] ---"
        for (k in field) {
            split(k, a, SUBSEP)
            if (a[1] == idx) print a[2] " = " field[k]
        }
    }
    print ""
    print "maxField=" maxField
}