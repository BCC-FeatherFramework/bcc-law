LawConfig = {
    -- Language of the MDT when the player's account has no Core locale: 'en' or 'ro'.
    DefaultLocale = 'en',
    -- Proposed initial values; these never register a job, issue a commission,
    -- grant a role, or create a jurisdiction automatically.
    Departments = {
        new_hanover = { label = 'New Hanover', jobKey = 'police', minGradeOrdinal = 0,
            licenseKey = 'peace_officer', jurisdictionKey = 'bcc-law:new_hanover', jurisdictionType = 'county',
            judicial = {jobKey='judge',licenseKey='judicial_commission',minGradeOrdinal=0} }
    },
    MaxDepartments = 16,
    -- Justice case types offered in the MDT (Justice JurisdictionConfig.CaseTypes).
    CaseTypes = { 'criminal', 'investigation', 'citation', 'civil', 'administrative' },
    DefaultCaseType = 'criminal',
    -- Starter penal code, registered only by the console command LawSetupStatutes.
    -- Recommended fines (minor units: 2500 = 25.00 dollars) and custody ranges are
    -- advice for officers and judges; Justice never applies them automatically.
    Statutes = {
        new_hanover = {
            { name = 'disorderly_conduct', title = 'Disorderly conduct', category = 'public_order', severityClass = 'infraction',
                recommendedFine = { min = 500, max = 2500 } },
            { name = 'public_intoxication', title = 'Public intoxication', category = 'public_order', severityClass = 'infraction',
                recommendedFine = { min = 500, max = 1500 } },
            { name = 'trespassing', title = 'Trespassing', category = 'property', severityClass = 'misdemeanor',
                recommendedFine = { min = 1000, max = 5000 }, recommendedCustodySeconds = { min = 0, max = 600 } },
            { name = 'theft.petty', title = 'Petty theft', category = 'theft', severityClass = 'misdemeanor',
                recommendedFine = { min = 2500, max = 10000 }, recommendedCustodySeconds = { min = 300, max = 900 } },
            { name = 'theft.grand', title = 'Grand theft', category = 'theft', severityClass = 'felony',
                recommendedFine = { min = 10000, max = 50000 }, recommendedCustodySeconds = { min = 900, max = 3600 } },
            { name = 'theft.horse', title = 'Horse theft', category = 'theft', severityClass = 'felony',
                recommendedFine = { min = 15000, max = 50000 }, recommendedCustodySeconds = { min = 1800, max = 3600 } },
            { name = 'robbery', title = 'Robbery', category = 'violence', severityClass = 'felony',
                recommendedFine = { min = 20000, max = 75000 }, recommendedCustodySeconds = { min = 1800, max = 5400 } },
            { name = 'assault', title = 'Assault', category = 'violence', severityClass = 'misdemeanor',
                recommendedFine = { min = 2500, max = 15000 }, recommendedCustodySeconds = { min = 600, max = 1800 } },
            { name = 'assault.aggravated', title = 'Aggravated assault', category = 'violence', severityClass = 'felony',
                recommendedFine = { min = 15000, max = 50000 }, recommendedCustodySeconds = { min = 1800, max = 5400 } },
            { name = 'homicide', title = 'Homicide', category = 'violence', severityClass = 'felony',
                recommendedCustodySeconds = { min = 3600, max = 14400 } },
            { name = 'resisting_arrest', title = 'Resisting arrest', category = 'obstruction', severityClass = 'misdemeanor',
                recommendedFine = { min = 2500, max = 10000 }, recommendedCustodySeconds = { min = 300, max = 1200 } },
            { name = 'weapon.brandishing', title = 'Brandishing a weapon', category = 'weapons', severityClass = 'misdemeanor',
                recommendedFine = { min = 1500, max = 7500 } }
        }
    },
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
    Custody = { InteractionDistance = 3.0, Facilities = {
        valentine = { label = 'Valentine', department = 'new_hanover',
            x = -273.05, y = 810.97, z = 119.37, radius = 10.0 }
    } },
    -- bcc-doorlocks door IDs of each facility's cells. Law only asks doorlocks to
    -- lock them on booking and jail placement; doorlocks stays the single owner.
    Doors = { Facilities = {
        -- valentine = { 12, 13 },
    } },
    -- Citizen alerts (/lawalert) and shots-fired reports go to on-duty officers of
    -- the department through Core notifications, with a temporary map blip.
    Alerts = { CitizenCooldownSeconds = 120, MaxMessageLength = 200, BlipSeconds = 120,
        ShotsFired = { Enabled = true, CooldownSeconds = 60, Areas = {
            valentine = { department = 'new_hanover', label = 'Valentine', x = -281.0, y = 793.0, z = 118.0, radius = 120.0 }
        } } }
}
