#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Load data/app_icon.png from the bundle (see linux/CMakeLists.txt). PNG is required
// for GdkPixbuf; .ico often fails on Linux and breaks the taskbar / Steam Deck tile.
static gchar* resolve_bundle_icon_path() {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", NULL);
  if (exe_path == NULL) {
    return NULL;
  }
  g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
  const gchar* const candidates[] = {"app_icon.png", "app_icon.ico", NULL};
  for (int i = 0; candidates[i] != NULL; i++) {
    g_autofree gchar* path =
        g_build_filename(exe_dir, "data", candidates[i], NULL);
    if (g_file_test(path, G_FILE_TEST_EXISTS)) {
      return g_strdup(path);
    }
  }
  return NULL;
}

static void try_set_application_icon_from_bundle() {
  g_autofree gchar* icon_path = resolve_bundle_icon_path();
  if (icon_path == NULL) {
    return;
  }
  GError* error = NULL;
  if (!gtk_window_set_default_icon_from_file(icon_path, &error)) {
    g_warning("Failed to load app icon: %s",
              error != NULL ? error->message : "unknown");
    g_clear_error(&error);
  }
}

static void try_set_window_icon(GtkWindow* window) {
  g_autofree gchar* icon_path = resolve_bundle_icon_path();
  if (icon_path == NULL) {
    return;
  }
  GError* error = NULL;
  if (!gtk_window_set_icon_from_file(window, icon_path, &error)) {
    g_warning("Failed to set window icon: %s",
              error != NULL ? error->message : "unknown");
    g_clear_error(&error);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  try_set_application_icon_from_bundle();
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, APPLICATION_NAME);
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, APPLICATION_NAME);
  }

  try_set_window_icon(window);
  gtk_window_set_role(window, APPLICATION_ID);

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  g_set_application_name(APPLICATION_NAME);
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
