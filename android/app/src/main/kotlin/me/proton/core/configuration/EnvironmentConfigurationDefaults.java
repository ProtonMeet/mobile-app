package me.proton.core.configuration;

import proton.android.meet.BuildConfig;

public class EnvironmentConfigurationDefaults {
    /// use meet-api.host for now
    public static final String host = BuildConfig.MEET_HOST;
    public static final String proxyToken = "";
    public static final String apiPrefix = "wallet-api";
    public static final String baseUrl = "https://wallet-api." + host;
    public static final String apiHost = "wallet-api." + host;
    public static final String hv3Host = "verify." + host;
    public static final String hv3Url = "https://verify." + host;
    public static final Boolean useDefaultPins = false;
}
