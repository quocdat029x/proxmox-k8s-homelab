#!/bin/bash
kubespray_image=${kubespray_image}
kubespray_data_dir=${kubespray_data_dir}

# Patch Kubespray bug: sha256 should be checksum
sudo docker run --rm \
    --mount type=bind,source="$kubespray_data_dir/inventory.ini",dst=/inventory/sample/inventory.ini \
    --mount type=bind,source="$kubespray_data_dir/addons.yml",dst=/inventory/sample/group_vars/k8s_cluster/addons.yml \
    --mount type=bind,source="$kubespray_data_dir/k8s-cluster.yml",dst=/inventory/sample/group_vars/k8s_cluster/k8s-cluster.yml \
    --mount type=bind,source="$kubespray_data_dir/id_rsa",dst=/root/.ssh/id_rsa \
    $kubespray_image bash -c \
        "cd /kubespray && sed -i 's/sha256:/checksum:/g' roles/kubernetes-apps/argocd/tasks/main.yml && \
         ansible-playbook -i /inventory/sample/inventory.ini -u ubuntu -b cluster.yml -f 3"
