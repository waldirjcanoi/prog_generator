#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

gen_path="~/prog_generator"
GENERATOR_PROG=$gen_path

config_dir="$GENERATOR_PROG/config"
tmpl_dir="$GENERATOR_PROG/templates"

# props file can be provided as first arg, otherwise default
input_config_file="${1:-fallback-config.conf}"

# template file can be provided as second arg, otherwise default
input_template_file="${2:-fallback-template.tmpl}"

function usage() {
  echo "Usage: [props.conf] [template.tmpl]"
  exit 2
}

if [ "${input_config_file:-}" = "-h" ] || [ "${input_config_file:-}" = "--help" ]; then
  usage
fi

if [ "${input_template_file:-}" = "-h" ] || [ "${input_template_file:-}" = "--help" ]; then
  usage
fi

config_file="$config_dir/$input_config_file"

if [ ! -f "$config_file" ]; then
  echo "ERROR: props file not found: $config_file" >&2
  usage
fi

object=$(basename "$config_file" .conf)

# extract entity name from the config (fallback to object if missing)
entity=$(grep -E '^[[:space:]]*entity[[:space:]]*=' "$config_file" | head -n1 | sed -E 's/^[^=]*=[[:space:]]*//; s/^[[:space:]'"'"'"]+//; s/[[:space:]'"'"'"]+$//')

if [ -z "${entity:-}" ]; then
  # if no entity in config, use a capitalized object name as fallback
  entbase=$(basename "$object")
  entity="$(tr '[:lower:]' '[:upper:]' <<< "${entbase:0:1}")${entbase:1}"
fi

template_file="$tmpl_dir/$input_template_file"

if [ ! -f "$template_file" ]; then
  echo "ERROR: template not found: $template_file" >&2
  exit 3
fi

template=$(basename "$template_file" .tmpl)

out_dir="generated"
mkdir -p "$out_dir"
out_file="$out_dir/${template}.java"
AWK_RENDERER="scripts/render.awk"

if [ ! -f "$AWK_RENDERER" ]; then
  echo "ERROR: renderer not found at $AWK_RENDERER" >&2
  exit 4
fi

BLOCKS="${BLOCKS:-header,body_vo_properties,body_constructor_args,body_constructor_props,body_constructors,body_creators,body_creator_values,body_setters_getters,footer}"

echo "Rendering:"
echo "  props:    $config_file"
echo "  template: $template_file"
echo "  output:   $out_file"
echo "  blocks:   $BLOCKS"
echo

awk -v BLOCKS="$BLOCKS" -f "$AWK_RENDERER" "$config_file" "$template_file" > "$out_file"
rc=$?

if [ $rc -ne 0 ]; then
  echo "ERROR: renderer failed (rc=$rc)" >&2
  exit $rc
fi

echo "Generated: $out_file"
