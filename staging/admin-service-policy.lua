-- STAGING ONLY. Append to feather-admin/configs/service_policy.lua.
-- Exact broker and delegated resource; no player authorization is conferred.
Config.servicePolicy['feather-justice']=Config.servicePolicy['feather-justice'] or {}
Config.servicePolicy['feather-justice']['bcc-law']=Config.servicePolicy['feather-justice']['bcc-law'] or {}
Config.servicePolicy['feather-justice']['bcc-law']['justice.definition.manage']=true
Config.servicePolicy['feather-justice']['bcc-law']['justice.status.view']=true
Config.servicePolicy['feather-justice']['bcc-law']['justice.sentence.progress']=true

-- Citation lifecycle only. Contracts, not Justice or Law, settles debtor wallets.
Config.servicePolicy['feather-contracts']=Config.servicePolicy['feather-contracts'] or {}
Config.servicePolicy['feather-contracts']['feather-justice']={
    ['contracts.obligation.issue']=true,
    ['contracts.obligation.cancel']=true
}
