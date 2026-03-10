package com.vsmartcard.remotesmartcardreader.app;

import androidx.annotation.Nullable;

enum TransportMode {
    TCP("tcp"),
    BLUETOOTH_CLIENT("bluetooth_client"),
    BLUETOOTH_SERVER("bluetooth_server");

    static final String DEFAULT_PREFERENCE_VALUE = "bluetooth_server";

    private final String preferenceValue;

    TransportMode(String preferenceValue) {
        this.preferenceValue = preferenceValue;
    }

    String preferenceValue() {
        return preferenceValue;
    }

    static TransportMode fromPreference(@Nullable String value) {
        if ("bluetooth".equalsIgnoreCase(value)) {
            return BLUETOOTH_SERVER;
        }
        for (TransportMode mode : values()) {
            if (mode.preferenceValue.equalsIgnoreCase(value)) {
                return mode;
            }
        }
        return TCP;
    }
}
