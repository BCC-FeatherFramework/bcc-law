fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
name 'bcc-law'
author 'BCC Team'
description 'Native Feather law gameplay: foundation and Justice case integration'
version '2.0.0-alpha.5'
shared_script 'shared/results.lua'
server_scripts { 'config.lua', 'server/foundation.lua', 'server/access.lua', 'server/routes.lua', 'server/legal_routes.lua', 'server/custody.lua', 'server/setup.lua', 'server/acceptance.lua', 'server/main.lua' }
client_script 'client/main.lua'
dependencies {
    'feather-core', 'feather-character', 'feather-jobs', 'feather-licenses',
    'feather-justice'
}

ui_page 'ui/index.html'
files { 'ui/index.html', 'ui/app.js', 'ui/style.css' }
