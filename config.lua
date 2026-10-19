LawConfig = {
    -- Proposed initial values; these never register a job, issue a commission,
    -- grant a role, or create a jurisdiction automatically.
    Departments = {
        new_hanover = { label = 'New Hanover', jobKey = 'police', minGradeOrdinal = 0,
            licenseKey = 'peace_officer', jurisdictionKey = 'bcc-law:new_hanover',
            judicial = {jobKey='judge',licenseKey='judicial_commission',minGradeOrdinal=0} }
    },
    MaxDepartments = 16,
    Armory = { Stations = {
        valentine = {department='new_hanover',label='Valentine armory',x=-273.05,y=810.97,z=119.37,radius=3.0,
            items={water={label='Water ration',kind='item',itemName='water',quantity=1},
                cattleman={label='Service revolver',kind='weapon',definitionId='revolver_cattleman',quantity=1}}}
    } },
    Execution = { DefaultFacility = 'valentine', Facilities = {
        valentine = { entrance = {x=-273.05,y=810.97,z=119.37},
            exit = {x=-276.76,y=815.19,z=119.21}, radius = 3.0 },
        sisika = { entrance = {x=3359.64,y=-668.57,z=45.78},
            exit = {x=2670.49,y=-1545.06,z=45.97}, radius = 300.0 }
    }, Tasks = {
        valentine_maintenance = {label='Valentine station maintenance',x=-280.0,y=810.0,z=119.37,radius=2.0,seconds=30}
    } },
    Restraints = { InteractionDistance = 3.0, EscortDistance = 6.0, MaxSeconds = 900 },
    Evidence = { Lockers = {
        valentine = { department = 'new_hanover', label = 'Valentine evidence',
            x = -273.05, y = 810.97, z = 119.37, radius = 3.0, maxItems = 1000, maxWeight = 10000 }
    } },
    -- Booking is confirmed only when officer + subject are physically here.
    -- Coordinates retained from the uploaded configuration; no automatic teleport.
    Custody = { InteractionDistance = 3.0, Facilities = {
        valentine = { label = 'Valentine', department = 'new_hanover',
            x = -273.05, y = 810.97, z = 119.37, radius = 10.0 }
    } }
}
