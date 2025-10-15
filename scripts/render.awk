# Renderer with per-field vs single-shot block handling.
# Usage:
#   awk -v BLOCKS="header,body_vo_properties,..." -v PERFIELD="body_vo_properties,body_constructor_args,body_constructor_props,body_creator_values,body_setters_getters" -f scripts/render.awk props.conf template.tmpl > out.java

function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }

# parse property lines (prefer '=' then ':')
function parse_prop_line(line,    seppos, keypart, valpart, k) {
    seppos = index(line, "=")
    if (seppos == 0) seppos = index(line, ":")
    if (seppos == 0) return
    keypart = trim(substr(line, 1, seppos-1))
    valpart  = trim(substr(line, seppos+1))
    if (keypart ~ /\[[0-9]+\]$/) return
    if (current_section ~ /^field(_|)([0-9]+)$/) {
        if (match(current_section, /([0-9]+)$/, a)) k = a[1] + 0
        else { maxField++; k = maxField }
        field[k, keypart] = valpart
        fieldKeys[keypart] = 1
        if (k > maxField) maxField = k
    } else {
        globals[keypart] = valpart
    }
}

# Read props (first ARGV)
FILENAME == ARGV[1] {
    if (FNR == 1) current_section = "global"
    line = $0; gsub(/\r/, "", line); line = trim(line)
    if (line == "" || line ~ /^[;#]/) next
    if (match(line, /^\[([^\]]+)\]/, sect)) { current_section = trim(sect[1]); next }
    parse_prop_line(line)
    next
}

# collect template content
{ tmpl = tmpl $0 "\n"; next }

# lookup: field-scoped then globals
function resolve_key(key, idx,    v) {
    if (idx > 0 && ((idx, key) in field)) return field[idx, key]
    if (key in globals) return globals[key]
    return ""
}

# single-pass token replacement (no recursion)
function replace_tokens_once(s, idx,    pos, out, m1, m2, p1, l1, p2, l2, startPos, len, token, key, val) {
    pos = 1; out = ""
    while (pos <= length(s)) {
        m1 = match(substr(s, pos), /\$\{[^}]+\}/)
        if (m1) { p1 = pos + RSTART - 1; l1 = RLENGTH } else { p1 = 0; l1 = 0 }
        m2 = match(substr(s, pos), /\{\{[^}]+\}\}/)
        if (m2) { p2 = pos + RSTART - 1; l2 = RLENGTH } else { p2 = 0; l2 = 0 }
        if (p1 == 0 && p2 == 0) { out = out substr(s, pos); break }
        if (p1 != 0 && (p2 == 0 || p1 <= p2)) {
            startPos = p1; len = l1; token = substr(s, startPos+2, len-3)
        } else {
            startPos = p2; len = l2; token = substr(s, startPos+2, len-4)
        }
        if (startPos > pos) out = out substr(s, pos, startPos-pos)
        key = trim(token)
        val = resolve_key(key, idx)
        out = out val
        pos = startPos + len
    }
    return out
}

# helper
function capitalize(x,    f,r) { if (x=="") return ""; f = substr(x,1,1); r = substr(x,2); return toupper(f) r }

END {
    if (tmpl == "") exit

    # defaults / derive helpers
    if (!("entity" in globals)) globals["entity"] = ""
    if (!("module" in globals)) globals["module"] = ""
    if (!("instance" in globals)) {
        ent = globals["entity"]
        if (ent != "") globals["instance"] = tolower(substr(ent,1,1)) substr(ent,2)
        else globals["instance"] = ""
    }

    # split package -> root + package (so template ${root}.${package}.${module} works)
    if ("package" in globals) {
        pkg = globals["package"]
        if (index(pkg, ".") > 0) {
            n = split(pkg, parts, ".")
            globals["root"] = parts[1]
            rest = ""
            for (j = 2; j <= n; j++) rest = (rest==""?parts[j]:rest "." parts[j])
            globals["package"] = rest
        } else {
            globals["root"] = globals["package"]; globals["package"] = ""
        }
    } else { globals["root"]=""; globals["package"]="" }

    # synthesize per-field helpers
    for (i = 1; i <= maxField; i++) {
        if (!((i,"propName") in field)) field[i,"propName"] = ((i,"name") in field) ? field[i,"name"] : ""
        if (!((i,"propType") in field)) field[i,"propType"] = ((i,"typeObj") in field) ? field[i,"typeObj"] : "Object"
        field[i,"propNameCap"] = capitalize(field[i,"propName"])
    }

    # composite globals
    cargs = ""; cprops = ""; cvalues = ""
    for (i = 1; i <= maxField; i++) {
        pt = field[i,"propType"]; pn = field[i,"propName"]
        if (i > 1) cargs = cargs ", "
        cargs = cargs pt " " pn
        cprops = cprops "    this." pn " = " pn ";\n"
        if (i > 1) cvalues = cvalues ", "
        cvalues = cvalues pn
        field[i,"separator"] = (i < maxField) ? "," : ""
    }
    globals["cargs"] = cargs; globals["cprops"] = cprops; globals["cvalues"] = cvalues

    # determine blocks list (BLOCKS var preferred, else auto-detect)
    blockSpec = BLOCKS
    if (blockSpec == "") {
        start = 1; nb = 0
        while (match(substr(tmpl, start), /\$\{([A-Za-z0-9_]+)_init\}/, m)) {
            name = m[1]
            if (!(name in seen)) { nb++; blocks[nb] = name; seen[name]=1 }
            start += RSTART + RLENGTH - 1
        }
        nblocks = nb
    } else {
        nblocks = split(blockSpec, tmp, ",")
        for (j=1; j<=nblocks; j++) blocks[j] = trim(tmp[j])
    }

    # build per-field set (from PERFIELD var or default list)
    perSpec = PERFIELD
    if (perSpec == "" && ("PERFIELD" in ENVIRON)) perSpec = ENVIRON["PERFIELD"]
    if (perSpec == "") perSpec = "body_vo_properties,body_constructor_args,body_constructor_props,body_creator_values,body_setters_getters"
    nper = split(perSpec, ptoks, ",")
    for (p=1; p<=nper; p++) perField[trim(ptoks[p])] = 1

    out = tmpl

    # process each block: repeat only if configured per-field, otherwise process once as global
    for (bi = 1; bi <= nblocks; bi++) {
        name = blocks[bi]
        if (name == "") continue
        startTag = "\\$\\{" name "_init\\}"
        endTag   = "\\$\\{" name "_end\\}"
        guard = 0
        while (match(out, startTag)) {
            guard++; if (guard > 500) { print "ERROR: block guard for " name > "/dev/stderr"; break }
            sp = RSTART
            rest = substr(out, sp + RLENGTH)
            if (!match(rest, endTag)) break
            inner = substr(rest, 1, RSTART-1)
            prefix = substr(out, 1, sp-1)
            suffix = substr(rest, RSTART + RLENGTH)
            # decide per-field or single-shot
            if ((name in perField) && perField[name] && maxField > 0) {
                rep = ""
                for (i = 1; i <= maxField; i++) rep = rep replace_tokens_once(inner, i)
                out = prefix rep suffix
            } else {
                # single-shot: replace tokens once in inner using globals (idx=0)
                single = replace_tokens_once(inner, 0)
                out = prefix single suffix
            }
            # continue processing the same block in case appears again elsewhere
        }
    }

    # final global replacements
    out = replace_tokens_once(out, 0)
    printf "%s", out
}