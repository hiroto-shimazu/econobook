FROM ubuntu:22.04

# 基本ツール
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl git xz-utils unzip zip ca-certificates \
    libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

# Flutter 安定版を配置
RUN git clone -b stable https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

# 初回に必要キャッシュ作成（doctor でSDK類の初期化）
RUN flutter --version