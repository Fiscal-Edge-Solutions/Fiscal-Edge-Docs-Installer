CREATE VIEW [dbo].[ZraPurchase] 
AS
SELECT TOP 5
	CAST(Inv.AutoIndex AS VARCHAR(20)) AS Id,
	Inv.InvNumber AS InvoiceNumber,
	'0' AS OriginalInvoiceNumber,
	COALESCE(NULLIF(MS.ulJCDestinationCountryCode, ''), 'ZM') AS DestinationCountryCode,
	COALESCE(NULLIF(MS.ucJCZRALOCALPURCHASEORDER, ''), NULL) AS LocalPurchaseOrder,
	'000' AS BranchId,
    '01' AS PaymentTypeCode,
	RepName AS IssuerName,
	CAST(iRepID AS VARCHAR(20)) AS IssuerId,
	CASE -- Check the SAGE currency mapping and update this script accordingly. 
		WHEN CurrencyCode IS NULL THEN 'ZMW'
		ELSE CurrencyCode
	END AS CurrencyType,
	CAST((SELECT TOP 1 fExchangeRate FROM [_btblJCInvoiceLines] WHERE iJobNumID = Inv.AutoIndex) AS DECIMAL(20,4)) AS "ConversionRate",
    Inv.CustomerName AS CustomerName,
    Inv.CustomerName AS "BuyerTaxAccountName",
    'S' AS ReceiptTypeCode,
    Inv.cTaxNumber AS CustomerTpin,
	Inv.InvDate AS SaleDate,
    NULL AS RefundReasonCode
FROM [_bvJobNumFull] as Inv
LEFT JOIN [_btblJCMaster] MS ON Inv.InvNumber = MS.cFinalInvoiceNo 
LEFT JOIN FiscalInfo Fisc ON Inv.InvNumber = Fisc.InvoiceNumber
WHERE inv.DocType = 1 AND Fisc.InvoiceNumber IS NULL
END
GO


CREATE PROCEDURE ZraJobCardInvoiceItem(@RefId VARCHAR(50))
AS
BEGIN
SET NOCOUNT ON
SELECT 
	CAST(iJobNumID AS VARCHAR(50)) AS RefId,
	CAST(ROW_NUMBER() OVER (ORDER BY [idJCInvoiceLines]) AS INT) AS ItemSequenceNumber, 
	cDescription AS ItemDesc, 
	COALESCE(st.ucIIUNSPSC, '10101504') AS ItemClassificationCode,
	COALESCE(NULLIF(st.Code, ''), 'URI') AS ItemCode,
	Tr.cFiscalTaxLabel AS TaxLabel,
	COALESCE(st.uliiPackagingUnitCode, 'NT') AS PackagingUnitCode,
	COALESCE(st.ulIIQuantityUnitCode, 'NO') AS QuantityUnitCode,
	0.0 AS DiscountAmount,
	CAST(fQuantity AS DECIMAL(20,4)) AS Quantity,
	CASE 
		WHEN fQuantity IS NULL OR fQuantity = 0 THEN 0
		ELSE CAST(
			CASE 
				WHEN fExchangeRate IS NULL OR fExchangeRate = 1 THEN fLineTotIncl 
				ELSE fLineTotInclForeign 
			END / fQuantity AS DECIMAL(20, 8)
		)
	END AS "UnitPrice", 
	CASE 
		WHEN fExchangeRate = 1 THEN  CAST(fLineTotIncl AS DECIMAL(20, 4))
		ELSE CAST(fLineTotInclForeign AS DECIMAL(20, 4)) 
	END as "TotalAmount", 
	1 as isTaxInclusive,
	0.0 AS RRP
from [_btblJCInvoiceLines] It
WITH (NOLOCK)
LEFT JOIN _bvStockFull st ON st.StockID = It.iStockID
LEFT JOIN TaxRate Tr ON Tr.idTaxRate = It.iTaxTypeID
WHERE iJobNumID = @RefId AND fLineTotExcl != 0
END
GO


ALTER PROCEDURE [dbo].[UpdateFiscalDetails]
    @Signature NVARCHAR(255),
    @InternalData NVARCHAR(255),
	@InvNumber NVARCHAR(255),
	@InvoiceType NVARCHAR(255),
	@InvoiceSequence NVARCHAR(255),
	@QrCode NVARCHAR(255),
	@VsdcDate NVARCHAR(255),
	@IsJobCard INT
AS
BEGIN
	IF @IsJobCard = 0
		BEGIN
			UPDATE InvNum
			SET cDPOrdServiceTaskNo = @Signature, cDSOrdServiceTaskNo = @InternalData, 
			cDSMExtOrderNum = @InvoiceSequence, cHash = @QrCode
			WHERE InvNumber = @InvNumber;
		END
	ELSE
		BEGIN
			UPDATE JobNum
			SET Message1 = @Signature, Message2 = @InternalData, 
			Message3 = @InvoiceSequence, cHash = @QrCode
			WHERE InvNumber = @InvNumber;
		END
END;