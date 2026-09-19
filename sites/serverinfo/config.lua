-- Server info site content. SERVER ONLY. Everything here is placeholder text: replace it with your
-- own rulebook, staff list and changelog.
Config.serverinfo = {
    name    = 'Life In The 90s',
    tagline = 'Welcome to the server. Read the rules, meet the team and see what is new.',

    discord = {
        label  = 'Join our Discord',
        invite = 'discord.gg/your-invite',
        text   = 'Our Discord is where you apply for jobs, get support and hear about updates.',
    },

    rules = {
        {
            title = 'General',
            items = {
                'Treat every player and staff member with respect.',
                'No cheating, exploiting or using bugs for gain. Report them to staff.',
                'Stay in character at all times in the city.',
            },
        },
        {
            title = 'Roleplay',
            items = {
                'Value your life. Act realistically when you are in danger or injured.',
                'No random killing or harassment without a roleplay reason.',
                'Do not use out-of-character information in the city.',
            },
        },
        {
            title = 'Crime',
            items = {
                'Crime needs a proper roleplay build-up and a reason.',
                'Follow the minimum number of police for each heist.',
                'Do not take hostages or start a robbery inside a safe zone.',
            },
        },
    },

    staff = {
        { name = 'Owner Name',   role = 'Owner' },
        { name = 'Admin Name',   role = 'Head Admin' },
        { name = 'Support Name', role = 'Moderator' },
    },

    changelog = {
        {
            version = '1.0',
            date    = '2026-09-19',
            items   = {
                'The in-game Browser is here, with the Los Santos Government, CoverCompare and Careers sites.',
            },
        },
    },
}
