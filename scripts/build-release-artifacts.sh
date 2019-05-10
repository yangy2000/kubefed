#!/usr/bin/env bash

# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script automates the building of artifacts for a release.
#
# Reference:  docs/releasing.md


set -o errexit
set -o nounset
set -o pipefail

RELEASE_TAG="${1-}"
if [[ ! "${RELEASE_TAG}" ]]; then
  >&2 echo "usage: $0 <release tag of the form v[0-9]+.[0-9]+.[0-9]+>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." ; pwd)"
RELEASE_VERSION="${RELEASE_TAG:1:${#RELEASE_TAG}-1}"

pushd "${ROOT_DIR}"
  # Build release artifacts for kubefedctl
  make bin/kubefedctl-linux
  make bin/kubefedctl-darwin
  pushd "${ROOT_DIR}/bin"
    for host_os in linux darwin; do
      TAR_FILENAME="kubefedctl-${RELEASE_VERSION}-${host_os}-amd64.tgz"
      BINARY_FILENAME="kubefedctl-${host_os}"
      # The binary is built with a platform suffix, but should be archived without it.
      tar cvzf "${TAR_FILENAME}" --transform="flags=r;s|${BINARY_FILENAME}|kubefedctl|" "${BINARY_FILENAME}"
      sha256sum "${TAR_FILENAME}" > "${TAR_FILENAME}.sha"
      mv "${TAR_FILENAME}" "${TAR_FILENAME}.sha" "${ROOT_DIR}/"
    done
  popd

  # Build release artifacts for the helm chart
  pushd "${ROOT_DIR}/charts"
    # Update the image tag for the chart
    sed -i.backup "s+\(  tag: \)canary+\1${RELEASE_TAG}+" federation-v2/values.yaml

    # Update the chart version
    sed -i.backup "s+\(version: \).*+\1${RELEASE_VERSION}+" federation-v2/Chart.yaml

    helm package federation-v2

    # Update the repo index (will need to be committed)
    helm repo index . --merge index.yaml --url="https://github.com/kubernetes-sigs/federation-v2/releases/download/${RELEASE_TAG}"

    sha256sum "federation-v2-${RELEASE_VERSION}.tgz" > "federation-v2-${RELEASE_VERSION}.tgz.sha"
    mv federation-v2-${RELEASE_VERSION}.tgz* "${ROOT_DIR}/"

    # Revert the chart changes (should not be committed)
    mv federation-v2/values.yaml.backup federation-v2/values.yaml
    mv federation-v2/Chart.yaml.backup federation-v2/Chart.yaml
  popd
popd
