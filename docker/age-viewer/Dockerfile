#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Local override of the Apache AGE Viewer image.
#
# The upstream project (apache/age-viewer, last release v1.0.0, Dec 2021) is
# effectively unmaintained and all released tags use Node 14, which reached
# EOL in April 2023.  minimatch@10.2.5 (a transitive dependency) requires
# Node 18/20/>=22, causing `yarn install` to abort with:
#
#   error minimatch@10.2.5: The engine "node" is incompatible with this
#   module. Expected version "18 || 20 || >=22". Got "14.18.2"
#
# This Dockerfile clones the upstream source at the v1.0.0 immutable tag and
# builds it on node:22-alpine.  Two extra changes are required for Node 22
# compatibility:
#
#   1. NODE_OPTIONS=--openssl-legacy-provider for the React (webpack 4)
#      frontend build — react-scripts@4.x uses the legacy OpenSSL hash
#      provider removed in Node 17+.
#   2. `grep -E` instead of `egrep` — egrep was removed from Alpine >=3.19.
#
# The upstream entrypoint, port (3001), and runtime behaviour are unchanged.

FROM node:22-alpine

# Fetch upstream source at the pinned v1.0.0 tag.
RUN apk --no-cache add git && \
    git clone --depth 1 --branch v1.0.0 \
        https://github.com/apache/age-viewer.git /app-src && \
    apk del git

RUN mkdir -p /app && apk --no-cache add bash

WORKDIR /app/backend

# Stage source and entrypoint from the upstream clone, then drop the clone.
RUN cp -r /app-src/frontend /app/frontend && \
    cp -r /app-src/backend  /app/backend  && \
    cp /app-src/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh && \
    ln -s /usr/local/bin/docker-entrypoint.sh / && \
    rm -rf /app-src

# Build frontend (React/webpack 4) and backend (Babel transpile), then strip
# dev artifacts.  NODE_OPTIONS is required for the frontend build on Node >=17.
RUN set -eux; \
    apk --no-cache --virtual .build-deps add less openssh; \
    \
    cd /app/frontend; \
    yarn install; \
    NODE_OPTIONS=--openssl-legacy-provider yarn run build; \
    ls -A | grep -v 'build' | xargs rm -rf; \
    \
    cd /app/backend; \
    yarn install; \
    yarn run build; \
    ls -A | grep -E -v "^(build|package|node_modules|sql)" | xargs rm -rf; \
    \
    cd /; \
    rm -rf "$(yarn cache dir)"; \
    apk del .build-deps

ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3001
