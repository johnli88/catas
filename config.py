

config = dict(
    user_action = "",
    assess_name = "myAssessment",
    assess_type = "both",
    input_csv_file = f"C:\\temp\\myAssessment.csv",
    count_csv_file = "",
    output_folder = f"C:\\temp\\assessmentOutput",
    output_report_name = "myAssessment",
    output_report_format = "all",
    validation_type = "ValidateBoth",
    target_platform = "SQLdb",
    db_list = '',
    collect_time = 240,
    tenant_id = '',
    sub_id = '',
    client_id = '',
    link_list = [],
    target_cost = '',
    config_file_full_name = ''
)

def print_config(title):
    if (title):
        print(title, " Configuration: ")
    for key in config:
        print(f"           {key} = {config[key]}")
    