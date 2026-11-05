import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const workflow = readFileSync(new URL('../.github/workflows/generated-retry.yml', import.meta.url), 'utf8');
const script = workflow.split('          script: |\n')[1].replace(/^            /gm, '');
const execute = new Function('github', 'context', 'core', `return (async () => {${script}})()`);
const message = 'The job was not acquired by Runner of type hosted even after multiple attempts';
assert.match(workflow, /run_attempt < 3/);
assert.match(workflow, /workflow_run.conclusion == 'failure'/);
for (const [conclusion, steps, annotation, expected] of [
  ['cancelled', [], message, 1],
  ['failure', [{started_at: '2026-11-05T12:00:00Z'}], message, 0],
  ['cancelled', [], 'Cancelled by user', 0],
  ['cancelled', [{started_at: '2026-11-05T12:00:00Z'}], message, 0],
]) {
  let retries = 0;
  const job = {name: 'regenerate', conclusion, steps, check_run_url: 'https://api.github.com/repos/o/r/check-runs/123'};
  const listJobs = () => {};
  const listAnnotations = () => {};
  const github = {
    paginate: async endpoint => endpoint === listJobs ? [job] : [{message: annotation}],
    rest: {
      actions: {listJobsForWorkflowRunAttempt: listJobs, reRunWorkflow: async () => { retries++; }},
      checks: {listAnnotations},
    },
  };
  await execute(github, {repo: {owner: 'o', repo: 'r'}, payload: {workflow_run: {id: 1, run_attempt: 1}}}, {notice() {}});
  assert.equal(retries, expected, `${conclusion}: ${annotation}`);
}
console.log('PASS: unallocated job retries; script failure, user cancellation and started jobs do not; attempts capped at three');
