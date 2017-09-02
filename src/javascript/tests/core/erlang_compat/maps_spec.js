import test from 'ava';
import Core from '../../../lib/core';

test('find', (t) => {
  let myMap = new Map();
  let result = Core.maps.find('t', myMap);
  t.is(result, Symbol.for('error'));

  myMap = 'Hello';
  result = Core.maps.find('t', myMap);
  t.deepEqual(result.values, [Symbol.for('badmap'), myMap]);

  myMap = new Map([['t', 'b']]);
  result = Core.maps.find('t', myMap);
  t.deepEqual(result.values, [Symbol.for('ok'), 'b']);
});

test('fold', async (t) => {
  const myMap = new Map([['a', 1], ['b', 2]]);
  const result = await Core.maps.fold((k, v, acc) => acc + v, 0, myMap);
  t.is(result, 3);
});
