project('singularity-contacts', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-contacts"', language: 'c')
subdir('po')

gtk_dep  = dependency('gtk4')
gee_dep  = dependency('gee-0.8')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

executable('singularity-contacts',
  files('src/vcard.vala', 'src/books.vala', 'src/account_book.vala', 'src/avatar.vala', 'src/editor.vala', 'src/search.vala', 'src/hub.vala', 'src/window.vala', 'src/app.vala'),
  dependencies: [gtk_dep, gee_dep, libsingularity_dep],
  install: true
)

vcard_test = executable('contacts-test',
  files('src/vcard.vala', 'tests/vcard_test.vala'),
  dependencies: [gee_dep, dependency('gio-2.0')],
)
test('vcard', vcard_test)

shared_module('singularity-contacts-widget',
  files('src/vcard.vala', 'src/avatar.vala', 'widget/favorites_widget.vala'),
  dependencies: [gtk_dep, gee_dep, libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.contacts.favorites.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

install_data('data/search-providers/dev.sinty.contacts.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.contacts.service.in',
  output: 'dev.sinty.contacts.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/dev.sinty.contacts.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.contacts.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
