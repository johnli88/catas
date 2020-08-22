from flask import Flask, render_template, url_for, flash, redirect, request, jsonify
from forms import ValidationForm, AssessmentForm, CollectionForm
from wtforms.validators import ValidationError
from werkzeug.utils import secure_filename
import subprocess
from config import config, print_config
import sys
import os.path
import json
import csv
import webbrowser
import time

app = Flask(__name__)
app.config['SECRET_KEY'] = 'CATAS2020'
app.config['SEND_FILE_MAX_AGE_DEFAULT'] = 0

posts = [
    {
        'action': 'Validate',
        'description': 'Validate input SQL Server CSV file',
        'page': 'validate',
    },
    {
        'action': 'Assess',
        'description': 'Asses your SQL Server feature parity and compability',
        'page': 'assess',
    },
    {
        'action': 'Collect',
        'description': 'Collect your SQL Server workload and cost estimation',
        'page': 'collect',
    },
    {
        'action': 'Manage',
        'description': 'Save current assessment or load existing assessment',
        'page': 'manage',
    }
]

def set_link(htmllist, name):
    sqldblink = dict(type="sqldb", description="", link="", file="")
    sqlmilink = dict(type="sqlmi", description="", link="", file="")
    sqldblink['description'] = name
    sqlmilink['description'] = name
    sqldblink['link'] = "file:///" + os.path.join(config['output_folder'], "prices-" + name + "_SQL_DB.html")
    sqlmilink['link'] = "file:///" + os.path.join(config['output_folder'], "prices-" + name + "_SQL_MI.html")
    sqldblink['file'] = "prices-" + "_SQL_DB.html"
    sqlmilink['file'] = "prices-" + "_SQL_MI.html"
    htmllist.append(sqldblink)
    htmllist.append(sqlmilink)
    return


def get_html(assessType):
    print("assess type inside get_html(): ", assessType)
    #templist = result.split()
    htmllist = []
    error = ""
    if assessType == 'sku':
        set_link(htmllist, config['assess_name'])
    else:
        try:
            with open(config['input_csv_file'], newline='') as csvfile:
                servers = csv.reader(csvfile, delimiter=',')
                line_count = 0
                for server in servers:
                    if line_count:
                        set_link(htmllist, server[0])
                    else:
                        line_count += 1
        except IOError as e:
            error = f"I/O error({e.errno}): {e.strerror}"

    print("htmllist: ", htmllist)
    return error, htmllist

def execute_script(script, params):
    cmd = ["powershell","-ExecutionPolicy", "Bypass", ".\\{0} {1}".format(script, params)]
    print(f"cmd: {cmd}")

    #p = subprocess.Popen(cmd, stdout = subprocess.PIPE, stderr=subprocess.PIPE, stdin=subprocess.PIPE)
    #out,err = p.communicate()
    cp = subprocess.run(cmd, universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    print(f"return code: {cp.returncode}")
    print('stderr: ' + str(cp.stderr))
    print('stdout: ' + str(cp.stdout))
    if (cp.stderr):
        #raise Exception('Error: ' + str(err))
        return 'Error ' + str(cp.stderr)
    return str(cp.stdout)

def show_cost(sqldb, sqlmi):
    #chrome_path = 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe %s' 
    chrome_path = 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe' 
    if os.path.isfile(chrome_path):
        chrome_path += " %s"
        if sqldb == 'true' or sqlmi == 'true':
            for x in config['link_list']:
                if (sqldb == 'true' and x['type'] == 'sqldb') or (sqlmi == 'true' and x['type'] == 'sqlmi'):
                    try:
                        webbrowser.get(chrome_path).open_new_tab(x['link'])
                        time.sleep(1.5)
                    except Exception as e:
                        print("Exception in calling webbrowser. Please check Chrome settings", str(e)) 
        else:
            print("both sqldb & sqlmi are FALSE")
    else:
        print("Chrome does not exist.")
    
    return

def save_config(file_name):
    print(f"saving file {file_name}")
    try:
        with open(file_name, "w+") as outfile:
            outfile.write(json.dumps(config, indent = 4))
        return 0
    except IOError as e:
        print(f"I/O error({e.errno}): {e.strerror}")
        return 1
    except:
        print("Unexpected error:", sys.exc_info()[0])
        return 2
    return 0

def load_config(file_name):
    print(f"loading file {file_name}")
    try:
        with open(file_name, "r") as infile:
            dict_object = json.load(infile)
            for key in config:
                config[key] = dict_object[key] 
        return 0
    except IOError as e:
        print(f"I/O error({e.errno}): {e.strerror}")
        return 1
    except:
        print("Unexpected error:", sys.exc_info()[0])
        return 2
    return 0



@app.route("/")
@app.route("/home")
def home():
    config['user_action'] = "home"
    return render_template('home.html', posts=posts)


@app.route("/validate", methods=['GET', 'POST'])
def validate():
    config['user_action'] = "validate"
    print_config('start validation')
    form = ValidationForm(assessname=config['assess_name'], filename=config['input_csv_file'],
                          validationType=config['validation_type'])
    if request.method == 'POST':
        print("This is a POST.")
        if form.validate_on_submit():
            assessName = form.assessname.data
            print(f"Assessment name: {assessName}")
            filename = form.filename.data
            #filename = secure_filename(form.filename.data.filename)
            print(f"csv file name: {filename}")
            #form.filename.data.save('uploads/' + filename)
            validationType = form.validationType.data
            print(f"you chose: {validationType}")
            flash(f'Start server connection validation ...', 'info')
            result = str(execute_script("catas.ps1", f"-AssessName {assessName} -InputFile {filename} -{validationType}"))
            if result[0:5] == "Error":
                errorMessage = result if len(result) <= 200 else result[0:200]
                flash(errorMessage, 'danger')
                #raise ValidationError('SQL server host connection validation failed, please check host name and credentials.')
            else:
                #flash(f"PowerShell script good {result}", 'success')
                flash(f'Validation successful for {filename}!', 'success')
            form = ValidationForm(assessname=assessName, filename=filename, validationType=validationType)

            #return redirect(url_for('validate'))
            #return render_template('validate.html', title='Validate', form=form)
    else:
        print("This is not a POST.")
    #print(form.filename.data)
    return render_template('validate.html', title='Validate', form=form)

@app.route("/assess", methods=['GET', 'POST'])
def assess():
    config['user_action'] = "assess"
    print_config("start assess stage")
    form = AssessmentForm(assessname=config['assess_name'], filename=config['input_csv_file'], 
        outputFolder=config['output_folder'], reportName=config['output_report_name'], reportFormat=config['output_report_name'],
        assessType=config['assess_type'], target=config['target_platform'])
    if form.validate_on_submit():
        flash(f'Start SQL Server Azure migration assessment ...', 'info')
        params = f"-AssessName {config['assess_name']} -InputFile {config['input_csv_file']} -OutputFolder {config['output_folder']} \
                    -ReportName {config['output_report_name']} -AssessType {config['assess_type']} -Target {config['target_platform']}"
        result = str(execute_script("catas.ps1", params))
        result = 'Success'
        if result[0:5] == "Error":
            errorMessage = result if len(result) <= 200 else result[0:200]
            flash(errorMessage, 'danger')
            #raise AssessError('SQL server host connection Assess failed, please check host name and credentials.')
        else:
            #flash(f"PowerShell script good {result}", 'success')
            flash(f'Assessment successful!', 'success')
        form = AssessmentForm(assessname=config['assess_name'], filename=config['input_csv_file'], 
            outputFolder=config['output_folder'], reportName=config['output_report_name'], reportFormat=config['output_report_name'],
            assessType=config['assess_type'], target=config['target_platform'])

    return render_template('assess.html', title='Assess', form=form)


@app.route("/collect", methods=['GET', 'POST'])
def collect():
    config['user_action'] = "collect"
    print_config("start collect stage")
    form = CollectionForm(assessname=config['assess_name'], filename=config['input_csv_file'], 
            outputFolder=config['output_folder'], reportFormat=config['output_report_name'],
            assessType=config['assess_type'], dblist=config['db_list'], collectTime=config['collect_time'],
            tenantid=config['tenant_id'], subid=config['sub_id'], clientid=config['client_id'])
    if request.method == 'POST' and "azure_cost" in request.form:
        print("azure_cost sqldb: ", request.form['sqldb'])
        print("azure_cost sqlmi: ", request.form['sqlmi'])
        show_cost(request.form['sqldb'], request.form['sqlmi'])
    else:
        print("azure_cost is empty")
        if (config['db_list']):
            templist = config['db_list'].split(",")
            dblist = "'"
            for db in templist:
                dblist += ' "' + db.strip() + '"'
            dblist += "'"
        else:
            dblist = ""
        print("dblist: ", dblist)

        if form.validate_on_submit():
            print("collect forms validated!!!!!!!!!!!!!!")
            if (config['assess_type'] == 'workload'):
                params = f"-AssessName {config['assess_name']} -InputFile {config['input_csv_file']} \
                          -OutputFolder {config['output_folder']} \
                          -AssessType {config['assess_type']} -WorkloadTime {config['collect_time']}"
            elif (config['assess_type'] == 'sku'):
                config['count_csv_file'] = config['input_csv_file']
                #config['output_report_name'] = f"prices-{config['assess_name']}.html"
                if (dblist):
                    params = f"-AssessName {config['assess_name']} -CountFile {config['count_csv_file']} \
                        -OutputFolder {config['output_folder']} -AssessType {config['assess_type']} \
                        -TenantId {config['tenant_id']} -SubscriptionId {config['sub_id']} -ClientId {config['client_id']} \
                        -DatabaseNames {dblist}"
                else:
                    params = f"-AssessName {config['assess_name']} -CountFile {config['count_csv_file']} \
                        -OutputFolder {config['output_folder']} -AssessType {config['assess_type']} \
                        -TenantId {config['tenant_id']} -SubscriptionId {config['sub_id']} -ClientId {config['client_id']}"
            else:    # workloadsku
                params = f"-AssessName {config['assess_name']} -InputFile {config['input_csv_file']} \
                    -OutputFolder {config['output_folder']} -AssessType {config['assess_type']} -WorkloadTime {config['collect_time']} \
                    -TenantId {config['tenant_id']} -SubscriptionId {config['sub_id']} -ClientId {config['client_id']}"
                
            error = ''
            result = str(execute_script("catas.ps1", params))
            if result[0:5] == "Error":
                errorMessage = result if len(result) <= 200 else result[0:200]
                flash(errorMessage, 'danger')
                #raise CollectError('SQL server host connection Assess failed, please check host name and credentials.')
            if config['assess_type'] != 'workload':
                #flash(f"PowerShell script good {result}", 'success')
                #result = "prices-localhost.html    prices-52.228.17.215.html  prices-RHDBDV16.html prices-40.85.219.90.html"
                print("inside collect() result: ", result)
                error, linklist = get_html(config['assess_type'])
                if error:
                    flash(error, 'danger')
                else:
                    flash(f'Collection successful!', 'success')
                    config['link_list'] = linklist
            form = CollectionForm(assessname=config['assess_name'], filename=config['input_csv_file'], 
                outputFolder=config['output_folder'], reportFormat=config['output_report_name'],
                assessType=config['assess_type'], dblist=config['db_list'], collectTime=config['collect_time'],
                tenantid=config['tenant_id'], subid=config['sub_id'], clientid=config['client_id'])
            if error:
                return render_template('collect.html', title='Collect', form=form)
            else:
                return render_template('collect.html', title='Collect', form=form, sidebar=True, 
                            sidebar_title='Azure Recommendation',
                            #sidebar_title='Manage',
                            sidebar_statement='Click following recommendations and submit for details.')
                #return render_template('collect.html', title='Collect', form=form)

    print("collect no validation")
    return render_template('collect.html', title='Collect', form=form)

@app.route("/manage", methods=['GET', 'POST'])
def manage():
    if request.method == 'POST':
        if "catas_save" in request.form:
            print("saving configuration file.")
            result = save_config(request.form['config_file'])
            if result:
                print('Error during saving configuration file.')
                return jsonify({'result' : 'err', 'msg' : 'Error during saving configuration file.'})
            else:
                print('Configuration saved into the file')
                return jsonify({'result' : 'suc', 'msg' : 'Successfully saved configuration!'})
        elif "catas_load" in request.form:
            print("loading configuration file.")
            result = load_config(request.form['config_file'])
            if result:
                print('Error during loading configuration file.')
                return jsonify({'result' : 'err', 'msg' : 'Error during loading configuration file.'})
            else:
                print('Configuration successfully loaded')
                # now redirect to the proper page from loaded configurations
                if not config['user_action'] or config['user_action'] == 'home':
                    #return render_template('home.html', posts=posts)
                    return jsonify({'result' : 'suc', 'msg' : '/' + config['user_action']})
                else:
                    # form = CollectionForm(assessname=config['assess_name'], filename=config['input_csv_file'], 
                    #                         validationType=config['validation_type'])
                    # return render_template('collect.html', title='Collect', form=form, posts=posts, sidebar=False)
                    # return redirect(url_for('collect'))
                    return jsonify({'result' : 'suc', 'msg' : '/' + config['user_action']})

        else:
            print("neither catas_save nor catas_load exists.")
    else:   # for non-POST    
        if config['user_action'] == 'assess':
            form = AssessmentForm(assessname=config['assess_name'], filename=config['input_csv_file'], 
                outputFolder=config['output_folder'], reportName=config['output_report_name'], 
                reportFormat=config['output_report_name'],
                assessType=config['assess_type'], target=config['target_platform'])
            return render_template('assess.html', title='Assess', form=form, sidebar=True,
                            sidebar_title='Manage', sidebar_statement='Save or load configurations.',
                            configFileFullName=config['config_file_full_name'])
        elif config['user_action'] == 'collect':
            #return redirect(url_for('validate'))
            form = CollectionForm(assessname=config['assess_name'], filename=config['input_csv_file'], 
                outputFolder=config['output_folder'], reportFormat=config['output_report_name'],
                assessType=config['assess_type'], dblist=config['db_list'], collectTime=config['collect_time'],
                tenantid=config['tenant_id'], subid=config['sub_id'], clientid=config['client_id'])
            return render_template('collect.html', title='Collect', form=form, posts=posts, sidebar=True,
                            sidebar_title='Manage', sidebar_statement='Save or load configurations.',
                            configFileFullName=config['config_file_full_name'])
        elif config['user_action'] == 'home':
            return render_template('home.html', posts=posts, sidebar=True,
                            sidebar_title='Manage', sidebar_statement='Load existing configuration.',
                            configFileFullName=config['config_file_full_name'])
        elif config['user_action'] == 'validate':
            #return redirect(url_for('validate'))
            form = ValidationForm(assessname=config['assess_name'], filename=config['input_csv_file'], 
                                        validationType=config['validation_type'])
            return render_template('validate.html', title='Validate', form=form, posts=posts, sidebar=True,
                            sidebar_title='Manage', sidebar_statement='Save or load configurations.',
                            configFileFullName=config['config_file_full_name'])
        else:
            print("unknow user action")
    return redirect(url_for('home'))


if __name__ == '__main__':
    app.run(debug=True)
