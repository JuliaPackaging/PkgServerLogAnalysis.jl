using PkgServerLogAnalysis

raw_data = parse_logfiles(PkgServerLogAnalysis.is_access_log; collect_results=false)
