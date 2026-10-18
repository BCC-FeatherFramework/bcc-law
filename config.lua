LawConfig = {
    -- Proposed initial values; these never register a job, issue a commission,
    -- grant a role, or create a jurisdiction automatically.
    Departments = {
        new_hanover = { label = 'New Hanover', jobKey = 'police', minGradeOrdinal = 0,
            licenseKey = 'peace_officer', jurisdictionKey = 'bcc-law:new_hanover' }
    },
    MaxDepartments = 16,
    -- Booking is confirmed only when officer + subject are physically here.
    -- Coordinates retained from the uploaded configuration; no automatic teleport.
    Custody = { InteractionDistance = 3.0, Facilities = {
        valentine = { label = 'Valentine', department = 'new_hanover',
            x = -273.05, y = 810.97, z = 119.37, radius = 10.0 }
    } }
}
