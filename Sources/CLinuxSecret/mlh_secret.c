#include "mlh_secret.h"
#include <libsecret/secret.h>

static const SecretSchema schema = {
    "com.github.kazu.inputmethod.mlh.openai",
    SECRET_SCHEMA_NONE,
    { { "application", SECRET_SCHEMA_ATTRIBUTE_STRING }, { NULL, 0 } }
};

static void copy_error(GError *source, char **destination) {
    if (destination) *destination = g_strdup(source ? source->message : "Secret Service error");
    if (source) g_error_free(source);
}

/* 1 = connected, 0 = no session service/bus, -1 = another connection error. */
static int service_status(char **error) {
    GError *failure = NULL;
    SecretService *service = secret_service_get_sync(SECRET_SERVICE_NONE, NULL, &failure);
    if (!service) {
        gboolean absent = failure && (
            g_error_matches(failure, G_DBUS_ERROR, G_DBUS_ERROR_SERVICE_UNKNOWN) ||
            g_error_matches(failure, G_DBUS_ERROR, G_DBUS_ERROR_NAME_HAS_NO_OWNER) ||
            g_error_matches(failure, G_IO_ERROR, G_IO_ERROR_NOT_FOUND) ||
            g_error_matches(failure, G_IO_ERROR, G_IO_ERROR_CONNECTION_REFUSED) ||
            g_error_matches(failure, G_IO_ERROR, G_IO_ERROR_NOT_CONNECTED));
        copy_error(failure, error);
        return absent ? 0 : -1;
    }
    g_object_unref(service);
    return 1;
}

int mlh_secret_read(char **value, char **error) {
    if (value) *value = NULL;
    if (error) *error = NULL;
    int service = service_status(error);
    if (service != 1) return service == 0 ? -1 : -2;
    GError *failure = NULL;
    char *password = secret_password_lookup_sync(&schema, NULL, &failure,
                                                  "application", "mlh", NULL);
    if (failure) {
        copy_error(failure, error);
        return -2;
    }
    if (!password) return 0;
    if (value) *value = password;
    else secret_password_free(password);
    return 1;
}

int mlh_secret_write(const char *value, char **error) {
    if (error) *error = NULL;
    if (service_status(error) != 1) return 0;
    GError *failure = NULL;
    gboolean result = secret_password_store_sync(&schema, SECRET_COLLECTION_DEFAULT,
                                                  "mlh OpenAI API key", value, NULL,
                                                  &failure, "application", "mlh", NULL);
    if (!result) copy_error(failure, error);
    return result;
}

int mlh_secret_clear(char **error) {
    if (error) *error = NULL;
    if (service_status(error) != 1) return 0;
    GError *failure = NULL;
    gboolean result = secret_password_clear_sync(&schema, NULL, &failure,
                                                  "application", "mlh", NULL);
    if (!result) copy_error(failure, error);
    return result;
}

void mlh_secret_free(char *value) {
    if (value) secret_password_free(value);
}

void mlh_secret_error_free(char *value) {
    g_free(value);
}
