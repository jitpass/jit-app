// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

/// AI Jobs fixtures, produced by marshalling the Go types in jitpass/jit's
/// internal/agent with json.Marshal (a throwaway test that printed them),
/// not typed by hand. Each is the Go output byte for byte, cut into pieces
/// only to fit the line length and joined back unchanged.
enum JobsFixture {
    static let list = [
        #"{"ok":true,"protocol":1,"jobs":[{"name":"notion-guests","dir":"/Users/x/custom_scripts/notion","argv"#,
        #"":[".venv/bin/python","list_guest_users.py"],"exe":"/Users/x/custom_scripts/notion/.venv/bin/python""#,
        #","profile":"notion","secrets":[{"var":"INTERNAL_DOMAINS","path":"notion/INTERNAL_DOMAINS","shown":tr"#,
        #"ue},{"var":"NOTION_API_KEY","path":"notion/NOTION_API_KEY"}],"ask":"each-time","outputs":["/Users/x/"#,
        #"reports"],"description":"List Notion guests","files":242,"state":"ready","approved_unix":1790300000,"#,
        #""runs":3,"last_run_unix":1790310000,"last_caller":"Claude","last_hidden":1},{"name":"wiz-inventory","#,
        #""dir":"/Users/x/custom_scripts/wiz","argv":["python","inventory.py"],"exe":"/usr/bin/python3","ask":"#,
        #""never","files":12,"state":"changed","changes":[{"path":"inventory.py","kind":"changed"}],"approved_"#,
        #"unix":1790200000,"last_caller":"Claude","last_refusal":"inventory.py changed since you approved it"}"#,
        #"]}"#
    ].joined()

    static let preview = [
        #"{"ok":true,"preview":{"dir":"/Users/x/custom_scripts/notion","exe":"/Users/x/custom_scripts/notion/."#,
        #"venv/bin/python","program":"list_guest_users.py","files":242,"secrets":[{"var":"NOTION_API_KEY","pat"#,
        #"h":"notion/NOTION_API_KEY"}],"ask":"each-time","prompt":"let AI run notion/list_guest_users.py with "#,
        #"1 notion secret"}}"#
    ].joined()

    static let refused = [
        #"{"ok":true,"preview":{"refusal":"job_allow: python3 -c runs a program written into the command itsel"#,
        #"f, so it can print the secrets it is given. Save it as a file and approve that file"}}"#
    ].joined()

    static let proposals = [
        #"{"ok":true,"proposals":[{"id":"c-1a2b3c4d","name":"notion-guests","spec":{"dir":"/Users/x/custom_scr"#,
        #"ipts/notion","argv":[".venv/bin/python","list_guest_users.py"],"profile":{"name":"notion","root":"/U"#,
        #"sers/x/custom_scripts/notion"},"ask":"each-time","path_env":"","home":""},"why":"To list Notion gues"#,
        #"ts for your access review.","by":"jit mcp","launched_by":"Claude","unix_time":1790320000}]}"#
    ].joined()

    static let pending = [
        #"{"unix_time":1790320100,"kind":"pending","op":"job_run","by":"jit mcp","launched_by":"Claude","cause"#,
        #"":"run notion/list_guest_users.py for Claude (3 secrets); it sees output, never the values","consent"#,
        #"_id":"c-9f8e7d6c","job":"notion-guests"}"#
    ].joined()

    static let proposalEvent = [
        #"{"unix_time":1790320000,"kind":"job_proposal","op":"job_request","launched_by":"Claude","cause":"To "#,
        #"list Notion guests.","consent_id":"c-1a2b3c4d","job":"notion-guests"}"#
    ].joined()

    static let allowReq = [
        #"{"op":"job_allow","job_name":"notion-guests","job_spec":{"dir":"/d","argv":["python","a.py"],"profil"#,
        #"e":{"name":"notion","root":"/d"},"ask":"each-time","shown":["INTERNAL_DOMAINS"],"outputs":["/r"],"pa"#,
        #"th_env":"/usr/bin","home":"/Users/x","description":"d","replace":true},"proposal_id":"c-1a2b3c4d"}"#
    ].joined()

    /// `job_list` from a jit that sends `stopped` and `outcome`: a job whose
    /// skips went on, one skipped once, one stopped, and one that runs.
    static let outcomeList = [
        #"{"ok":true,"jobs":[{"name":"notion-guests","dir":"/Users/x/custom_scripts/notion","argv":[".venv/bin"#,
        #"/python","list_guest_users.py"],"exe":"/usr/bin/python3","ask":"each-time","files":242,"state":"read"#,
        #"y","approved_unix":1790300000,"runs":3,"last_run_unix":1790310000,"last_caller":"Claude","last_refus"#,
        #"al":"the job's key couldn't be loaded (the key can't be used right now)","stopped":false,"outcome":""#,
        #"persisting-skip","skips":3,"skipping_since_unix":1790320000},{"name":"linear-issues","dir":"/Users/x"#,
        #"/custom_scripts/linear","argv":["python","issues.py"],"exe":"/usr/bin/python3","ask":"never","files""#,
        #":4,"state":"ready","approved_unix":1790300000,"runs":9,"last_run_unix":1790310000,"last_caller":"Cla"#,
        #"ude","last_refusal":"the job's key couldn't be loaded (the key can't be used right now)","stopped":f"#,
        #"alse,"outcome":"skip","skips":1,"skipping_since_unix":1790330000},{"name":"wiz-inventory","dir":"/Us"#,
        #"ers/x/custom_scripts/wiz","argv":["python","inventory.py"],"exe":"/usr/bin/python3","ask":"never","f"#,
        #"iles":12,"state":"changed","approved_unix":1790200000,"last_caller":"Claude","last_refusal":"invento"#,
        #"ry.py changed since you approved it","stopped":true,"outcome":"stop"},{"name":"gh-audit","dir":"/Use"#,
        #"rs/x/custom_scripts/gh","argv":["./audit.sh"],"exe":"/Users/x/custom_scripts/gh/audit.sh","ask":"nev"#,
        #"er","files":1,"state":"ready","approved_unix":1790200000,"stopped":false}]}"#
    ].joined()

    /// The four `job_run` outcomes, one event each.
    static let stopEvent = [
        #"{"unix_time":1790340000,"kind":"error","op":"job_run","by":"jit mcp","launched_by":"Claude","cause":"#,
        #""notion-guests: refused, list_guest_users.py changed since you approved it","labels":["notion/NOTION"#,
        #"_API_KEY"],"job":"notion-guests","job_outcome":"stop"}"#
    ].joined()

    static let stillStoppedEvent = [
        #"{"unix_time":1790340000,"kind":"error","op":"job_run","by":"jit mcp","launched_by":"Claude","cause":"#,
        #""notion-guests: refused, stopped: list_guest_users.py changed since you approved it","labels":["noti"#,
        #"on/NOTION_API_KEY"],"job":"notion-guests","job_outcome":"still-stopped"}"#
    ].joined()

    static let skipEvent = [
        #"{"unix_time":1790340000,"kind":"error","op":"job_run","by":"jit mcp","launched_by":"Claude","cause":"#,
        #""notion-guests: didn't run, the job's key couldn't be loaded (the key can't be used right now)","lab"#,
        #"els":["notion/NOTION_API_KEY"],"job":"notion-guests","job_outcome":"skip"}"#
    ].joined()

    static let persistingSkipEvent = [
        #"{"unix_time":1790340000,"kind":"error","op":"job_run","by":"jit mcp","launched_by":"Claude","cause":"#,
        #""notion-guests: didn't run 3 times in a row since Sep 26 09:14, the job's key couldn't be loaded (th"#,
        #"e key can't be used right now)","labels":["notion/NOTION_API_KEY"],"job":"notion-guests","job_outcom"#,
        #"e":"persisting-skip"}"#
    ].joined()
}
