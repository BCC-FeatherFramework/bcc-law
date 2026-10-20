Law = {}
function Law.Ok(value) return { ok = true, value = value } end
function Law.Err(code, message) return { ok = false, code = code, message = message } end
function Law.Uuid(value)
    return type(value) == 'string' and value:match(
        '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end
function Law.Text(value, maximum)
    return type(value) == 'string' and #value > 0 and #value <= maximum
        and value:find('%z') == nil and value:find('[\1-\8\11\12\14-\31\127]') == nil
end
function Law.Token(value, maximum)
    return type(value) == 'string' and #value > 0 and #value <= maximum
        and value:match('^[A-Za-z0-9][A-Za-z0-9_.:%-]*$') ~= nil
end
function Law.Fields(value, allowed)
    if type(value) ~= 'table' then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end
function Law.Copy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}; for key, child in pairs(value) do copy[key] = Law.Copy(child) end
    return copy
end
-- Text from the locale tables in locales/*.lua. Placeholders are named:
-- Law.T('ro', 'alert.shots', { area = 'Valentine' }). Unknown languages use
-- LawConfig.DefaultLocale (server) and then English.
function Law.Locale(lang)
    local tables = LawLocales or {}
    if type(lang) == 'string' and tables[lang] then return lang end
    local default = LawConfig and LawConfig.DefaultLocale
    if type(default) == 'string' and tables[default] then return default end
    return 'en'
end
function Law.T(lang, key, vars)
    local tables = LawLocales or {}
    local text = (tables[Law.Locale(lang)] or {})[key] or (tables.en or {})[key] or key
    if vars then
        text = text:gsub('{(%w+)}', function(name)
            local value = vars[name]
            return value ~= nil and tostring(value) or '{' .. name .. '}'
        end)
    end
    return text
end
