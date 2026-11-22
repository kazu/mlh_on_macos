#ifndef MLH_SECRET_H
#define MLH_SECRET_H

/* read: 1 = found, 0 = missing, -1 = service unavailable, -2 = lookup error. */
int mlh_secret_read(char **value, char **error);
int mlh_secret_write(const char *value, char **error);
int mlh_secret_clear(char **error);
void mlh_secret_free(char *value);
void mlh_secret_error_free(char *value);

#endif
