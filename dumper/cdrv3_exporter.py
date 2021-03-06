import pysolr
import json
import re
from datetime import datetime
import argparse
import os


def scroll_and_get_results(solr, q, **kwargs):
    results = []
    start = 0
    rows = 100
    hits = 100
    while start < hits:
        result = solr.search(q=q, rows=rows, start=start, **kwargs)
        hits = result.hits
        if hits == 0:
            break
        results += result.docs
        start +=rows
    return results


def get_parent(parent_id, solr):
    fl = ['content_type', 'id', 'crawler', 'raw_content', '*_hd', 'fetch_timestamp', 'url']
    fq = ['status:"FETCHED"', "id:"+parent_id]
    q = "*:*"
    results = solr.search(q=q, **{'fl':fl, 'fq':fq})
    if results.hits is not 1:
        print 'Got more than one hit for parent id {}, exiting...'.format(parent_id)
        exit(1)
    return results.docs[0]


def get_all_objects_for_parent(parent_id, solr):
    fl = ['content_type', 'id', 'crawler', 'raw_content', '*_hd', 'fetch_timestamp', 'url',
          'relative_path']
    fq = ['status:"FETCHED"', '!content_type:"text/html"',
          'parent:{}'.format(parent_id)]
    q = "*:*"

    return scroll_and_get_results(solr, q, **{'fq':fq, 'fl':fl})


def get_parent_id(solr):
    fq = ['status:"FETCHED"', 'content_type:text/html']
    q = "*:*"
    return scroll_and_get_results(solr, q, **{'fq':fq, 'fl':'id'})


def get_headers(doc):
    headers = {}
    for key in doc:
        match = re.match('(.*)(_[a-z])_hd', key)
        if match is not None:
            headers[match.group(1).encode('utf-8')] = doc.get(key)
    return {'response_headers':headers}


def prepare_objects_list(objects):
    objects_list = []
    for o in objects:
        obj_json = {}
        obj_json['obj_original_url'] = o.get('url')
        obj_json['obj_stored_url'] = o.get('relative_path')
        obj_json['content_type'] = o.get('content_type')
        obj_json['timestamp_crawl'] = o.get('fetch_timestamp')
        obj_json.update(get_headers(o))
        objects_list.append(obj_json)
    return objects_list


def prepare_cdrjson(parent, objects):
    team = "JPL"
    version = 3.1
    timestamp = datetime.utcnow().isoformat() + 'Z'
    cdr_json = {}
    cdr_json['_id'] = parent.get('id')
    cdr_json['content_type'] = parent.get('content_type')
    cdr_json['crawler'] = parent.get('crawler')
    cdr_json['objects'] = prepare_objects_list(objects)
    cdr_json['raw_content'] = parent.get('raw_content')
    cdr_json.update(get_headers(parent))
    cdr_json['team'] = team
    cdr_json['timestamp_crawl'] = parent.get('fetch_timestamp')
    cdr_json['timestamp_index'] = timestamp
    cdr_json['url'] = parent.get('url')
    cdr_json['version'] = version
    return cdr_json


def main(config):
    solr_url = "{}/{}".format(config['solr'], config['core'])
    solr = pysolr.Solr(solr_url)

    print("Starting output dump")

    parent_ids = get_parent_id(solr)
    dump_file = os.path.join("/projects/sce/data/dumper", "crawl-data-dump.jsonl")
    if os.path.exists(dump_file):
        os.rename(dump_file, "{}.old".format(dump_file))
    with open(dump_file, 'w') as fw:
        for parent_id in parent_ids:
            parent_doc = get_parent(parent_id['id'], solr)
            objects = get_all_objects_for_parent(parent_id['id'], solr)
            cdr_doc = prepare_cdrjson(parent_doc, objects)
            # print json.dumps(cdr_doc)
            try:
                # Writing to file
                fw.write(json.dumps(cdr_doc, encoding='utf-8') + "\n")
            except:
                print "Error writing {}".format(parent_id)
    print("Export complete")


if __name__ == '__main__':

    parser = argparse.ArgumentParser()
    default = os.path.join(os.path.dirname(os.path.realpath(__file__)),"dumper.config")
    parser.add_argument("--config_file", help="JSON Configuration file", default=default)
    args = parser.parse_args()
    config = {}
    with open(args.config_file, 'r') as f:
        config = json.load(f)

    main(config)
