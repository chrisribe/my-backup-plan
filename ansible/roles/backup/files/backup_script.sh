#!/bin/bash
# roles/backup/files/backup_script.sh

# Load backup configuration
source /etc/backup_config.conf

# Construct rsync exclude parameters
exclude_params=""
while IFS= read -r line; do
  if [[ $line == exclude_dir* ]]; then
    dir=$(echo $line | cut -d'=' -f2)
    exclude_params+="--exclude=$dir "
  fi
done < /etc/backup_config.conf

# Backup script content
echo "Running backup..."
rsync -av --delete $exclude_params "$source_dir" "$backup_dir"