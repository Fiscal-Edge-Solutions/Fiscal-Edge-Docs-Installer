-----------------------------------------------------------
----PurchaseInfo table to track fiscalised invoices
-----------------------------------------------------------
CREATE TABLE PurchaseInfo(
       Id identity,
       InvoiceNumber varchar(50),
       Message varchar(255),
       PRIMARY KEY (Id)
);
CREATE INDEX idxInvoiceNumber ON PurchaseInfo (InvoiceNumber);


----------------------------------------------------
--FiscalInfo table to track fiscalised invoices
----------------------------------------------------
CREATE TABLE FiscalInfo(
       Id identity,
       InvoiceNumber varchar(50),
       Message varchar(255),
       PRIMARY KEY (Id)
);
CREATE INDEX idxInvoiceNumber ON FiscalInfo (InvoiceNumber);


-----------------------------------------------------------
--ZraInvoice view to extract invoices for fiscalization
-----------------------------------------------------------
CREATE VIEW ZraInvoice AS 
SELECT TOP 1
    Header.DocumentNumber AS Id,
    Header.DocumentNumber AS InvoiceNumber,
    CASE 
        WHEN Header.DocumentType = 4 THEN COALESCE(NULLIF(RTRIM(OrigInv.Message03), ''), '0')
        ELSE '0'
    END AS OriginalNumber,
    COALESCE(NULLIF(RTRIM(Cust.UserDefined02), ''), 'ZM') AS DestinationCountryCode,
    Cust.UserDefined01 AS LocalPurchaseOrder,
    '000' AS BranchId,
    COALESCE(Acc.Description, 'ADMIN') AS IssuerName,
    COALESCE(Header.UserID, '1') AS IssuerId,
    CASE 
        WHEN Header.DocumentType = 3 THEN 'S'
        WHEN Header.DocumentType = 4 THEN 'R'
    END AS ReceiptTypeCode,
    '01' AS PaymentTypeCode,
    CASE --Please make sure this foreign currencies aligns with those configured in the users system
        WHEN Header.CurrencyCode = 1 THEN 'USD'
        WHEN Header.CurrencyCode = 2 THEN 'ZAR'
        WHEN Header.CurrencyCode = 3 THEN 'GBP'
        WHEN Header.CurrencyCode = 4 THEN 'EUR'
		ELSE 'ZMW'
    END AS CurrencyType,
    Header.Exchangerate AS ConversionRate,
    Cust.ExemptRef AS CustomerTpin,
    COALESCE(Cust.CustomerDesc, 'NONE') AS CustomerName,
    Header.DocumentDate AS SaleDate,
    '06' AS RefundReasonCode
FROM HistoryHeader Header
LEFT JOIN CustomerMaster Cust ON Cust.CustomerCode = Header.CustomerCode
LEFT JOIN AccountUser Acc ON Acc.ID = Header.UserID
LEFT JOIN HistoryHeader OrigInv ON OrigInv.DocumentNumber = Header.OrderNumber AND Header.DocumentType = 4
LEFT JOIN FiscalInfo FI ON Header.DocumentNumber = FI.InvoiceNumber
WHERE Header.DocumentType IN (3, 4)
  AND Header.DocumentDate > '2024-08-01'  -- This acts as a cutoff. You want to set this date to the date the smart invoice was setup so that only invoices issued from that day get fiscalized.
  AND FI.InvoiceNumber IS NULL;
  
  

-----------------------------------------------------------
--ZraStockMaster view to extract inventory items
-----------------------------------------------------------
CREATE VIEW ZraStockMaster AS
SELECT 
	I.ItemCode AS ItemCode, 
	I.Description AS Description,
	COALESCE(NULLIF(RTRIM(I.UserdefText02), ''), '10101504') AS ItemClassificationCode, 
	COALESCE(NULLIF(RTRIM(I.UnitSize), ''), 'EA') AS PackagingUnitCode, 
	COALESCE(NULLIF(RTRIM(I.UserdefText01), ''), 'NO') AS QuantityUnitCode, 
	St.OnHand as Quantity,
	'A' AS TaxLabel,
	COALESCE(NULLIF(RTRIM(I.CommodityCode), ''), 'ZM') AS OriginNationCode, 
	CASE
		WHEN I.Physical = 0 THEN '3'
		ELSE '2'
	END AS ItemTypeCode,
	'000' AS BranchId
FROM Inventory I
LEFT JOIN vwStockOnHand St ON I.ItemCode = St.ItemCode
WHERE I.Blocked = 0 AND St.StoreCode = ''


-----------------------------------------------------------
----ZraPurchase view to extract purchases
-----------------------------------------------------------
CREATE VIEW ZraPurchase AS
SELECT TOP 1
	Header.DocumentNumber AS Id,
	Header.DocumentNumber AS InvoiceNumber,
	Header.DocumentNumber AS SupplierInvoiceNumber,
	'0' AS OriginalNumber,
	CASE 
		WHEN Sup.UserDefined01 = '' OR Sup.UserDefined01 = 'local' THEN 'local' 
		ELSE Sup.UserDefined01
	END AS Origin,
	'000' AS BranchId,
	CASE
	 WHEN Acc.Description IS NULL THEN 'ADMIN'
	 ELSE Acc.Description
	END AS IssuerName,
	Header.UserID AS IssuerId,
	CASE 
        WHEN Header.DocumentType = 8 THEN 'S'
        WHEN Header.DocumentType = 9 THEN 'R'
    END AS ReceiptTypeCode,
	 '01' AS PaymentTypeCode,
	  CASE 
        WHEN Header.CurrencyCode = 1 THEN 'USD'
        WHEN Header.CurrencyCode = 2 THEN 'ZAR'
        WHEN Header.CurrencyCode = 3 THEN 'GBP'
        WHEN Header.CurrencyCode = 4 THEN 'EUR'
		ELSE 'ZMW'
    END AS CurrencyType,
	 Header.Exchangerate AS conversionRate,
	 Sup.ExemptRef AS CustomerTpin,
	 CASE 
		WHEN Sup.SupplDesc IS NULL THEN 'NONE'
		ELSE Sup.SupplDesc
	 END AS CustomerName,
	 Header.DocumentDate AS SaleDate,
	 '06' AS refundReasonCode
FROM HistoryHeader Header
LEFT JOIN SupplierMaster Sup ON Sup.SupplCode = Header.CustomerCode
LEFT JOIN AccountUser Acc ON Acc.ID = Header.UserID
LEFT JOIN PurchaseInfo Pur ON Header.DocumentNumber = Pur.InvoiceNumber
WHERE Header.DocumentType In (8,9)
	AND  Header.DocumentDate > '2024-08-01'
	AND Pur.InvoiceNumber IS NULL;