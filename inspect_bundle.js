const fs = require('fs');
const b = fs.readFileSync('./tgui-next/packages/tgui/public/tgui.bundle.js', 'utf8');
console.log('Around 7870:');
console.log(b.substring(7800, 7970));
