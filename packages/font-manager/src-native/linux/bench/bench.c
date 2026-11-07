/* Native benchmark / smoke test of libfontmanager.so: no JS involved.
   Usage: bench <fixtures dir>  (a folder of .ttf files; see run.sh) */
#include "font_manager.h"

#include <dirent.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e9 + ts.tv_nsec;
}

static void report(const char *name, double ns, long iterations) {
    double per = ns / iterations;
    if (per >= 1e6)
        printf("%-44s %10.3f ms/op  (%ld ops)\n", name, per / 1e6, iterations);
    else if (per >= 1e3)
        printf("%-44s %10.3f us/op  (%ld ops)\n", name, per / 1e3, iterations);
    else
        printf("%-44s %10.1f ns/op  (%ld ops)\n", name, per, iterations);
}

#define BENCH(name, iterations, body)                     \
    do {                                                  \
        long n_ = (iterations);                           \
        double t_ = now_ns();                             \
        for (long i = 0; i < n_; i++) { body; }           \
        report(name, now_ns() - t_, n_);                  \
    } while (0)

static int fail(const char *what) {
    fprintf(stderr, "FAIL: %s\n", what);
    return 1;
}

static atomic_int changes, events;

static void on_changed(int32_t reason, fm_face_t *face, void *user_data) {
    (void)reason, (void)face, (void)user_data;
    atomic_fetch_add(&changes, 1);
}

static void on_event(int32_t event, int32_t status, const fm_face_list_t *faces, const char *error, void *user_data) {
    (void)event, (void)status, (void)faces, (void)error, (void)user_data;
    atomic_fetch_add(&events, 1);
}

static char *read_file(const char *path, size_t *length) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    *length = (size_t)ftell(f);
    fseek(f, 0, SEEK_SET);
    char *data = malloc(*length);
    if (fread(data, 1, *length, f) != *length) *length = 0;
    fclose(f);
    return data;
}

#define MAX_FILES 32
static char files[MAX_FILES][1024];
static int file_count;

static atomic_int stop;

static void *reader(void *arg) {
    long *ops = arg;
    while (!atomic_load(&stop)) {
        fm_face_set_check("bold 16px 'Bench 0', serif", "abc");
        fm_resolve_family("'Bench 1', sans-serif", 700, false);
        (*ops)++;
    }
    return NULL;
}

static void *loader(void *arg) {
    int index = (int)(long)arg;
    char family[64];
    snprintf(family, sizeof family, "Thread %d", index);
    for (int i = 0; i < 50; i++) {
        fm_face_t *face = fm_face_new(family, files[(index + i) % file_count]);
        fm_face_set_add(face);
        fm_face_load(face);
        fm_face_set_delete(face);
        fm_face_unref(face);
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <fixtures dir>\n", argv[0]);
        return 2;
    }
    DIR *dir = opendir(argv[1]);
    if (!dir) return fail("fixtures dir");
    struct dirent *entry;
    while ((entry = readdir(dir)) && file_count < MAX_FILES) {
        size_t len = strlen(entry->d_name);
        if (len > 4 && strcmp(entry->d_name + len - 4, ".ttf") == 0)
            snprintf(files[file_count++], sizeof files[0], "%s/%s", argv[1], entry->d_name);
    }
    closedir(dir);
    if (file_count < 2) return fail("need at least two .ttf fixtures");

    char cache[] = "/tmp/fm-bench-XXXXXX";
    if (!mkdtemp(cache)) return fail("cache dir");
    fm_set_cache_dir(cache);
    fm_face_set_add_changed_listener(on_changed, NULL);
    fm_face_set_add_event_listener(on_event, NULL);

    printf("libfontmanager bench, %d fixture fonts\n\n", file_count);

    /* First registration of each file (FreeType parse + fontconfig) */
    fm_face_t *faces[MAX_FILES];
    double t = now_ns();
    for (int i = 0; i < file_count; i++) {
        char family[32];
        snprintf(family, sizeof family, "Bench %d", i);
        faces[i] = fm_face_new(family, files[i]);
        fm_face_set_add(faces[i]);
        if (fm_face_load(faces[i]) != FM_FACE_LOADED) return fail(files[i]);
    }
    report("load: new file (register + alias)", now_ns() - t, file_count);

    BENCH("load: already registered file", 2000, {
        fm_face_t *f = fm_face_new("Bench 0", files[0]);
        fm_face_load(f);
        fm_face_unref(f);
    });

    size_t length = 0;
    char *bytes = read_file(files[0], &length);
    BENCH("load: bytes (hash + cached file)", 200, {
        fm_face_t *f = fm_face_new_data("Bench Bytes", bytes, length);
        fm_face_load(f);
        fm_face_unref(f);
    });
    free(bytes);

    BENCH("check: loaded member face", 200000, fm_face_set_check("bold 16px 'Bench 0', serif", "abc"));
    BENCH("check: system family", 200000, fm_face_set_check("16px 'DejaVu Sans'", ""));
    BENCH("check: unknown family", 200000, fm_face_set_check("16px NoSuchFamily", ""));
    BENCH("resolve: cached", 1000000, fm_resolve_family("'Bench 1', sans-serif", 700, false));
    BENCH("resolve: generic", 1000000, fm_resolve_family("system-ui", 400, false));
    BENCH("resolve: uncached (cache reset per op)", 20000, {
        fm_face_set_add(faces[0]); /* no-op: already a member */
        fm_face_set_delete(faces[1]);
        fm_face_set_add(faces[1]);
        fm_resolve_family("'Bench 1', sans-serif", 700, false);
    });
    BENCH("match: font shorthand", 200000, fm_face_list_free(fm_face_set_match("italic 700 16px/1.2 'Bench 2', 'Bench 1', serif", "")));
    BENCH("set load: loaded faces", 200000, fm_face_list_free(fm_face_set_load("16px 'Bench 0'", "")));

    const char *css =
        "@font-face { font-family: 'Sheet A'; src: url(a.woff2) format('woff2'), url(a.ttf) format('truetype'); font-weight: 400; }\n"
        "@font-face { font-family: 'Sheet A'; src: url(b.woff2) format('woff2'); font-weight: 700; font-style: italic; }\n"
        "@font-face { font-family: \"Sheet B\"; src: local(B), url(data:font/ttf;base64,AAEAAA==); unicode-range: U+0-7F, U+4??; }\n";
    BENCH("stylesheet: parse 3 rules", 50000, fm_face_list_free(fm_parse_stylesheet(css, "https://fonts.test/css/fonts.css")));

    fm_descriptors_t *d = fm_descriptors_new("Desc");
    BENCH("descriptors: update(css)", 200000, fm_descriptors_update(d, "font-weight: 700; font-style: oblique 10deg; font-display: swap"));
    BENCH("descriptors: get + free", 1000000, fm_string_free(fm_descriptors_get(d, FM_DESCRIPTOR_STYLE)));
    fm_descriptors_unref(d);

    /* Threads: loaders add / load / delete while readers check and resolve */
    enum { READERS = 4, LOADERS = 4 };
    pthread_t readers[READERS], loaders[LOADERS];
    long reads[READERS] = {0};
    t = now_ns();
    for (int i = 0; i < READERS; i++) pthread_create(&readers[i], NULL, reader, &reads[i]);
    for (int i = 0; i < LOADERS; i++) pthread_create(&loaders[i], NULL, loader, (void *)(long)i);
    for (int i = 0; i < LOADERS; i++) pthread_join(loaders[i], NULL);
    atomic_store(&stop, 1);
    long total = 0;
    for (int i = 0; i < READERS; i++) {
        pthread_join(readers[i], NULL);
        total += reads[i];
    }
    double elapsed = now_ns() - t;
    printf("%-44s %10.3f ms     (%d loads, %ld check+resolve)\n", "threads: 4 loaders + 4 readers", elapsed / 1e6, LOADERS * 50, total);

    if (!fm_face_set_check("16px 'Bench 0'", "")) return fail("check after load");
    const char *family = fm_resolve_family("'Bench 0'", 400, false);
    if (!family || strcmp(family, fm_face_actual_family(faces[0])) != 0) return fail("resolve to the file's family");
    if (fm_face_set_size() != (size_t)file_count) return fail("set size");
    printf("\nresolve('Bench 0') -> %s; %d change callbacks, %d events\n", family, atomic_load(&changes), atomic_load(&events));

    for (int i = 0; i < file_count; i++) fm_face_unref(faces[i]);
    fm_face_set_clear();
    if (fm_face_set_size() != 0) return fail("clear");
    printf("ok\n");
    return 0;
}
