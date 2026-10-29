FROM reactnativecommunity/react-native-android:latest

ENV CI=true \
    GRADLE_USER_HOME=/gradle-cache \
    GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false"

ARG KEYSTORE_NAME=upload.keystore

WORKDIR /workspace

# Copy the Android project into this disposable image and make no host-source changes.
COPY ClipCascade_Mobile/src /workspace/ClipCascade_Mobile/src
COPY docker/android-builder/${KEYSTORE_NAME} /workspace/signing/${KEYSTORE_NAME}

WORKDIR /workspace/ClipCascade_Mobile/src
RUN npm ci

WORKDIR /workspace/ClipCascade_Mobile/src/android

# gradle.properties is intentionally gitignored; generate it from the CI template
# before Gradle evaluates app/build.gradle (including hermesEnabled).
RUN cp gradle.properties.ci gradle.properties

CMD ["./gradlew", "--no-daemon", "assembleRelease", "bundleRelease"]
