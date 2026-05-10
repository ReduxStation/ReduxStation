import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Section, Box, Button, Table } from '../components';

export const Vending = props => {
  const { act, data } = useBackend(props);
  let inventory;
  let custom = false;
  // Default each record bucket to an empty array. The first render runs
  // before BYOND has replied with static_data, so all four fields are
  // initially undefined; spreading undefined throws "is not iterable",
  // and a stray null in the spread output later trips
  // `Cannot read properties of undefined (reading 'price')` inside the
  // .map() below. Coalescing here means the first render produces an
  // empty product list cleanly, then re-renders once data arrives.
  const productRecords = data.product_records || [];
  const coinRecords = data.coin_records || [];
  const hiddenRecords = data.hidden_records || [];
  if (data.vending_machine_input) {
    inventory = data.vending_machine_input;
    custom = true;
  } else if (data.extended_inventory) {
    inventory = [...productRecords, ...coinRecords, ...hiddenRecords];
  } else {
    inventory = [...productRecords, ...coinRecords];
  }
  return (
    <Fragment>
      <Section
        title="User">
        {data.user && (
          <Box>
            Welcome, <b>{data.user.name}</b>,
            <b>{data.user.job || "Unemployed"}</b>!<br />
            Your balance is <b>${data.user.cash}</b>.
          </Box>
        ) || (
          <Box color="light-gray">
            No registered ID card!<br />
            Please contact your local HoP!
          </Box>
        )}
      </Section>
      <Section
        title="Products">
        <Table>
          {inventory.filter(p => p).map((product => {
            // Belt-and-braces: any record missing `price` defaults to 0
            // here so a single malformed entry doesn't crash the whole
            // .map() and surface as
            // `Cannot read properties of undefined (reading 'price')`.
            const price = product.price || 0;
            const free = ((data.department && data.user
              && data.department === data.user.department)
              || price === 0 || !data.onstation || !data.scanid);
            return (
              <Table.Row key={product.name}>
                <Table.Cell>
                  {product.base64 && (
                    <img src={`data:image/jpeg;base64,${product.img}`}
                      style={{
                        'vertical-align': 'middle',
                        'horizontal-align': 'middle',
                      }} />
                  ) || (
                    <span className={['vending32x32', product.path].join(' ')}
                      style={{
                        'vertical-align': 'middle',
                        'horizontal-align': 'middle',
                      }} />
                  )}
                  <b>{product.name}</b>
                </Table.Cell>
                <Table.Cell>
                  <Box color={custom
                    ? 'good'
                    : data.stock[product.name] <= 0
                      ? 'bad'
                      : data.stock[product.name] <= (product.max_amount / 2)
                        ? 'average'
                        : 'good'}>
                    {data.stock[product.name]} in stock
                  </Box>
                </Table.Cell>
                <Table.Cell>
                  {custom && (
                    <Button
                      content={data.access ? 'FREE' : '$' + price}
                      onClick={() => act('dispense', {
                        'item': product.name,
                      })} />
                  ) || (
                    <Button
                      disabled={(!free && (!data.user
                          || (price > data.user.cash)))
                          || data.stock[product.name] === 0}
                      content={free ? 'FREE' : '$' + price}
                      onClick={() => act('vend', {
                        'ref': product.ref,
                      })} />
                  )}
                </Table.Cell>
              </Table.Row>
            );
          }))}
        </Table>
      </Section>
    </Fragment>
  );
};
