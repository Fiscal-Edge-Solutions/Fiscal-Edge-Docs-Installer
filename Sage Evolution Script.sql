CREATE TABLE FiscalInfo(
       Id INT IDENTITY (1, 1) NOT NULL,
       InvoiceNumber nvarchar(50),
       Message nvarchar(max),
	   [CreateDate] DATETIME2 NULL DEFAULT (getdate()),
       PRIMARY KEY (Id)
);
CREATE INDEX idx_FiscalInfo_InvoiceNumber ON FiscalInfo (InvoiceNumber);


CREATE VIEW [dbo].[ZraInvoice] 
AS
 
SELECT TOP 5
	CAST(Inv.AutoIndex AS VARCHAR(20)) AS Id,
	Inv.InvNumber AS InvoiceNumber,
	CASE 
        WHEN Inv.DocType = 1 THEN COALESCE(OrigInv.cDSMExtOrderNum, '0')
        ELSE '0'
    END AS OriginalInvoiceNumber,
	COALESCE(NULLIF(RTRIM(OrigInv2.ulIDSOrdDestinationCountryCode), ''), NULLIF(RTRIM(OrigInv2.ulIDInvDestinationCountryCode), ''), null) AS DestinationCountryCode,
	COALESCE(NULLIF(RTRIM(OrigInv2.ucIDSOrdZRALOCALPURCHASEORDER), ''), NULLIF(RTRIM(OrigInv2.ucIDInvZRALOCALPURCHASEORDER), ''), null) AS LocalPurchaseOrder,
	'000' AS BranchId,
    '01' AS PaymentTypeCode,
	COALESCE((SELECT Ag.cAgentName FROM _rtblAgents Ag WHERE Inv.iINVNUMAgentID = Ag.idAgents), 'Admin') AS IssuerName,
	CAST(Inv.iINVNUMAgentID AS VARCHAR(20)) AS IssuerId,
	CASE -- Check the SAGE currency mapping and update this script accordingly. 
		WHEN Curr.CurrencyLink IS NULL THEN 'ZMW'
		WHEN Curr.CurrencyLink = 1 THEN 'USD'
		WHEN Curr.CurrencyLink = 2 THEN 'EUR'
		WHEN Curr.CurrencyLink = 3 THEN 'ZAR'
		ELSE 'ZMW'
	END AS CurrencyType,
	CAST(Inv.fExchangeRate AS DECIMAL(8,4)) AS "ConversionRate",
    Inv.cAccountName AS CustomerName,
    Inv.cAccountName AS "BuyerTaxAccountName",
    CASE -- Check the invoice type mapping and update accordingly
		WHEN Inv.DocType = 0 THEN 'S'
		WHEN Inv.DocType = 4 THEN 'S'
		WHEN inv.DocType = 1 THEN 'R'
	END AS ReceiptTypeCode,
    Inv.cTaxNumber AS CustomerTpin,
	Inv.InvDate AS SaleDate,
    CASE
		WHEN Inv.DocType = 1 THEN '06'
		ELSE NULL
	END AS RefundReasonCode
FROM [InvNum] as Inv
WITH (NOLOCK)
left JOIN Currency Curr on Curr.CurrencyLink = Inv.ForeignCurrencyID
LEFT JOIN (
    SELECT 
		InvNumber,
        cDSMExtOrderNum
    FROM _bvInvNumARFull 
	WITH (NOLOCK)
    WHERE DocType IN (0,4,1) 
      AND DocState = 4 
      AND InvNumber != '' 
      AND InvNumber IS NOT NULL 
      AND InvDate > '2024-06-30 00:00:00'
) AS OrigInv ON Inv.DeliveryNote = OrigInv.InvNumber
LEFT JOIN (
    SELECT 
		AutoIndex,
		ulIDSOrdDestinationCountryCode,
		ulIDInvDestinationCountryCode,
        ucIDInvZRALOCALPURCHASEORDER, 
        ucIDSOrdZRALOCALPURCHASEORDER 
    FROM _bvInvNumARFull 
	WITH (NOLOCK)
    WHERE DocType IN (0,4,1) 
      AND DocState = 4 
      AND InvNumber != '' 
      AND InvNumber IS NOT NULL 
      AND InvDate > '2024-06-30 00:00:00'
) AS OrigInv2 ON Inv.AutoIndex = OrigInv2.AutoIndex
LEFT JOIN FiscalInfo Fisc ON Inv.InvNumber = Fisc.InvoiceNumber
WHERE Inv.DocType in (0,4,1) AND Inv.DocState = 4
AND Inv.InvDate > '2024-06-30 00:00:00'
AND Inv.InvNumber != ''
AND Inv.InvNumber IS NOT NULL
AND Fisc.InvoiceNumber IS NULL
GO


CREATE PROCEDURE GetZraInvoiceItem(@RefId VARCHAR(50))
AS
BEGIN
SET NOCOUNT ON
SELECT 
	CAST(iInvoiceID AS VARCHAR(50)) AS RefId,
	iLineID AS ItemSequenceNumber, 
	cDescription AS ItemDesc, 
	COALESCE(st.ucIIUNSPSC, '10101504') AS ItemClassificationCode,
	CASE 
		WHEN (SELECT st.Code FROM _bvStockFull AS st WHERE st.StockID = It.iStockCodeID) IS NULL THEN 'URI'
		ELSE (SELECT st.Code FROM _bvStockFull AS st WHERE st.StockID = It.iStockCodeID)
		END AS ItemCode,
	CAST(fQtyProcessed AS DECIMAL(20,4)) AS Quantity,
	Tr.cFiscalTaxLabel AS TaxLabel,
	COALESCE(st.uliiPackagingUnitCode, 'NT') AS PackagingUnitCode,
	COALESCE(st.ulIIQuantityUnitCode, 'NO') AS QuantityUnitCode,
	0.0 AS DiscountAmount,
	CASE 
		WHEN fQuantity IS NULL OR fQtyProcessed = 0 THEN 0
		ELSE CAST(
			CASE 
				WHEN fQtyProcessedLineTotInclForeign IS NULL OR fQtyProcessedLineTotInclForeign = 0 THEN fQtyprocessedLineTotIncl 
				ELSE fQtyProcessedLineTotInclForeign 
			END / fQtyProcessed AS DECIMAL(20, 4)
		)
	END AS "UnitPrice", 
	--CASE
	--WHEN fQuantity = 0 THEN 0
	--ELSE CAST(fQuantityLineTotIncl/fQuantity AS DECIMAL(20,4)) END AS UnitPrice,
	CASE 
		WHEN fQtyProcessedLineTotInclForeign != 0 THEN  CAST(fQtyProcessedLineTotInclForeign AS DECIMAL(20, 4))
		ELSE CAST(fQtyprocessedLineTotIncl AS DECIMAL(20, 4)) 
	END as "TotalAmount", 
	--CAST(fQuantityLineTotIncl AS DECIMAL(20, 4))  AS TotalAmount,
	1 as isTaxInclusive,
	COALESCE(CAST(fRecommendedRetailPrice AS DECIMAL(20,4)), 0.0) AS RRP
from [_btblInvoiceLines] It
WITH (NOLOCK)
LEFT JOIN _bvStockFull st ON st.StockID = It.iStockCodeID
LEFT JOIN TaxRate Tr ON Tr.idTaxRate = It.iTaxTypeID
WHERE iInvoiceID = @RefId AND It.iOrigLineID = 0 AND fQtyProcessed != 0
END


CREATE VIEW [dbo].[ZraStockMaster] AS
SELECT 
	St.Code AS ITEMCODE,
	COALESCE(St.ucIIUNSPSC, '10101504') AS ItemClassificationCode,
	COALESCE(st.uliiPackagingUnitCode, 'NT') AS PackagingUnitCode,
	COALESCE(st.ulIIQuantityUnitCode, 'NO') AS QuantityUnitCode,
	CASE 
		WHEN St.ServiceItem = 1 THEN '3'
		ELSE '2'
	END AS ItemTypeCode,
	COALESCE(St.ulIIOriginCountryCode, 'CN') AS OriginNationCode,
	St.Description_1 AS Description,
	CASE 
		WHEN QtyInStock IS NULL THEN 0
		ELSE CAST(QtyInStock AS DECIMAL(18,4))
	END AS Quantity,
	Tr.cFiscalTaxLabel AS TaxLabel
FROM _bvStockFull St
WITH (NOLOCK)
LEFT JOIN TaxRate Tr ON Tr.idTaxRate = St.TTInvID
GO


CREATE PROCEDURE [dbo].[UpdateFiscalDetails]
    @Signature NVARCHAR(255),
    @InternalData NVARCHAR(255),
	@InvNumber NVARCHAR(255),
	@InvoiceType NVARCHAR(255),
	@InvoiceSequence NVARCHAR(255),
	@QrCode NVARCHAR(255),
	@VsdcDate NVARCHAR(255)
AS
BEGIN
    UPDATE InvNum
    SET cDPOrdServiceTaskNo = @Signature, cDSOrdServiceTaskNo = @InternalData, cDSMExtOrderNum = @InvoiceSequence
    WHERE InvNumber = @InvNumber;
END;


CREATE TABLE [dbo].[PurchaseInfo](
		[Id] [int] IDENTITY(1,1) NOT NULL,
		[InvoiceNumber] [nvarchar](50) NULL,
		[Message] [varchar](max) NULL,
		[CreateDate] DATETIME2 NULL DEFAULT (getdate()),
		PRIMARY KEY (Id)
		);
CREATE INDEX idx_PurchaseInfo_InvoiceNumber ON FiscalInfo (InvoiceNumber);


CREATE VIEW [dbo].[ZraPurchase] 
AS
SELECT TOP 5
	'local' AS Origin,
	CAST(Inv.AutoIndex AS VARCHAR(20)) AS Id,
	COALESCE(NULLIF(Inv.InvNumber, ''), Inv.GrvNumber) AS InvoiceNumber,
	COALESCE(NULLIF(Inv.InvNumber, ''), Inv.GrvNumber) AS SupplierInvoiceNumber,
	'0' AS OriginalInvoiceNumber,
	'000' AS BranchId,
    '01' AS PaymentTypeCode,
	(SELECT Ag.cAgentName FROM _rtblAgents Ag WHERE Inv.iINVNUMAgentID = Ag.idAgents) AS IssuerName,
	CAST(Inv.iINVNUMAgentID AS VARCHAR(20)) AS IssuerId,
	CASE -- Check the SAGE currency mapping and update this script accordingly. 
		WHEN Curr.CurrencyLink IS NULL THEN 'ZMW'
		WHEN Curr.CurrencyLink = 1 THEN 'USD'
		WHEN Curr.CurrencyLink = 2 THEN 'ZAR'
		WHEN Curr.CurrencyLink = 3 THEN 'EUR'
		ELSE 'ZMW'
	END AS CurrencyType,
	CAST(Inv.fExchangeRate AS DECIMAL(8,4)) AS "ConversionRate",
    Inv.cAccountName AS CustomerName,
    Inv.cAccountName AS "BuyerTaxAccountName",
    CASE -- Check the invoice type mapping and update accordingly
		WHEN Inv.DocType IN (2,5) THEN 'S'
		ELSE 'R'
	END AS ReceiptTypeCode,
    Inv.cTaxNumber AS CustomerTpin,
	Inv.InvDate AS SaleDate,
    CASE
		WHEN Inv.DocType = 1 THEN '06'
		ELSE NULL
	END AS RefundedReasonCode
FROM [InvNum] as Inv
WITH (NOLOCK) 
Left join _bvInvNumAPFull AS AP ON Inv.AutoIndex = AP.AutoIndex
left join Currency Curr on Curr.CurrencyLink = Inv.ForeignCurrencyID
LEFT JOIN PurchaseInfo Pur ON COALESCE(NULLIF(Inv.InvNumber, ''), Inv.GrvNumber) = Pur.InvoiceNumber
WHERE Inv.DocType in (2,5) AND Inv.OrigDocID != 0
AND Pur.InvoiceNumber IS NULL
AND Inv.InvDate > '2024-06-30 00:00:00'  --This acts a cutoff. you want to set this date to the date the smart invoice was setup so that only invoices issues from that day gets fiscalized. 
GO


CREATE PROCEDURE GetZraPurchaseItem(@RefId VARCHAR(50))
AS
BEGIN
SET NOCOUNT ON
SELECT
	CAST(iInvoiceID AS VARCHAR(50)) AS RefId,
	iLineID AS ItemSequenceNumber, 
	cDescription AS ItemDesc, 
	COALESCE(st.ucIIUNSPSC, '10101504') AS ItemClassificationCode,
	CASE 
		WHEN (SELECT st.Code FROM _bvStockFull AS st WHERE st.StockID = It.iStockCodeID) IS NULL THEN 'URI'
		ELSE (SELECT st.Code FROM _bvStockFull AS st WHERE st.StockID = It.iStockCodeID)
	END AS ItemCode,
	CAST(fQtyProcessed AS DECIMAL(20,4)) AS Quantity,
	Tr.cFiscalTaxLabel AS TaxLabel,
	COALESCE(st.uliiPackagingUnitCode, 'NT') AS PackagingUnitCode,
	COALESCE(st.ulIIQuantityUnitCode, 'NO') AS QuantityUnitCode,
	0.0 AS DiscountAmount,
	CASE 
		WHEN fQuantity IS NULL OR fQtyProcessed = 0 THEN 0
		ELSE CAST(
			CASE 
				WHEN fQtyProcessedLineTotInclForeign IS NULL OR fQtyProcessedLineTotInclForeign = 0 THEN fQtyprocessedLineTotIncl 
				ELSE fQtyProcessedLineTotInclForeign 
			END / fQtyProcessed AS DECIMAL(20, 4)
		)
	END AS "UnitPrice",  
	CASE 
		WHEN fQtyProcessedLineTotInclForeign != 0 THEN  CAST(fQtyProcessedLineTotInclForeign AS DECIMAL(20, 4))
		ELSE CAST(fQtyprocessedLineTotIncl AS DECIMAL(20, 4)) 
	END as "TotalAmount", 
	1 as isTaxInclusive,
	CAST(fRecommendedRetailPrice AS DECIMAL(20,4)) AS RRP
from [_btblInvoiceLines] It
WITH (NOLOCK)
LEFT JOIN _bvStockFull st ON st.StockID = It.iStockCodeID
LEFT JOIN TaxRate Tr ON Tr.idTaxRate = It.iTaxTypeID
WHERE iInvoiceID = @RefId AND It.iGrvLineID != 0
END
GO


