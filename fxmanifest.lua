fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
name 'bcc-law'
author 'BCC Team'
description 'Native Feather law gameplay on Feather Justice: MDT, field interactions, custody, court, jail, evidence and armory'
version '2.0.0-beta.1'
shared_scripts { 'shared/results.lua', 'locales/en.lua', 'locales/ro.lua' }
server_scripts { '@feather-mysql/lib/DB.lua', 'config.lua', 'server/foundation.lua', 'server/store.lua', 'server/routes.lua',
    'server/legal_routes.lua', 'server/custody.lua', 'server/restraints.lua', 'server/search.lua', 'server/evidence.lua', 'server/court.lua',
    'server/execution.lua', 'server/armory.lua', 'server/doors.lua', 'server/alerts.lua', 'server/setup.lua', 'server/acceptance.lua', 'server/main.lua' }
client_scripts { 'client/main.lua', 'client/restraints.lua', 'client/alerts.lua' }
dependencies {
    'feather-core', 'feather-character', 'feather-jobs', 'feather-licenses',
    'feather-justice', 'feather-mysql'
}

ui_page 'ui/index.html'
files { 'ui/index.html', 'ui/app.js', 'ui/style.css' }
