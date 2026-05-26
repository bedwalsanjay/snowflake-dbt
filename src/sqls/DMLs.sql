COPY INTO GLUE_DATA.ORDERS.ORDERS
FRoM @snowstage
FILES=('part-00000_orders.csv')
CREDENTIALS=(aws_key_id = '', aws_secret_key = '');

COPY INTO GLUE_DATA.ORDERS.CATEGORIES
FRoM @snowstage
FILES=('part-00000-categories.csv')
CREDENTIALS=(aws_key_id = '', aws_secret_key = '');

COPY INTO GLUE_DATA.ORDERS.CUSTOMERS
FRoM @snowstage
FILES=('part-00000-customers.csv')
CREDENTIALS=(aws_key_id = '', aws_secret_key = '');

COPY INTO GLUE_DATA.ORDERS.DEPARTMENTS
FRoM @snowstage
FILES=('part-00000-departments.csv')
CREDENTIALS=(aws_key_id = '', aws_secret_key = '');

COPY INTO GLUE_DATA.ORDERS.ORDER_ITEMS
FRoM @snowstage
FILES=('part-00000-order_items.csv')
CREDENTIALS=(aws_key_id = '', aws_secret_key = '');

COPY INTO GLUE_DATA.ORDERS.PRODUCTS
FRoM @snowstage
FILES=('part-00000-products.csv')
CREDENTIALS=(aws_key_id = '', aws_secret_key = '');