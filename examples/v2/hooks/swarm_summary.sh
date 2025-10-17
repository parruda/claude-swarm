#!/usr/bin/env bash
#
# Example swarm_stop hook: Generate execution summary
#
# This demonstrates:
# - Reading JSON from stdin
# - Accessing swarm metadata
# - Generating output
# - Exit 0 to continue (allow swarm to finish)

# Read JSON input from stdin
input=$(cat)

# Parse fields using jq (if available) or basic grep
if command -v jq &> /dev/null; then
    swarm_name=$(echo "$input" | jq -r '.swarm // "Unknown"')
    success=$(echo "$input" | jq -r '.success // false')
    duration=$(echo "$input" | jq -r '.duration // 0')
    cost=$(echo "$input" | jq -r '.total_cost // 0')
else
    swarm_name="Unknown"
    success="unknown"
fi

# Print summary to stderr (visible in logs)
echo "========================================" >&2
echo "Swarm Execution Summary" >&2
echo "========================================" >&2
echo "Swarm: $swarm_name" >&2
echo "Success: $success" >&2
echo "Duration: ${duration}s" >&2
echo "Cost: \$${cost}" >&2
echo "========================================" >&2

# Output success JSON
cat << EOF
{
  "success": true,
  "message": "Summary generated"
}
EOF

# Exit 0 to allow swarm to finish normally
exit 0
