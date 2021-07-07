#!/usr/bin/env node

require('./load_somes');

console.log(require.resolve('somes/sync_watch'));

require('somes/sync_watch');
